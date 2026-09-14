locals {
  # Default to us-west-2, flipped to us-east-1 if we're already out west.
  effective_replica_region = coalesce(var.replica_region, startswith(data.aws_region.current.region, "us-west") ? "us-east-1" : "us-west-2")
}

data "aws_region" "current" {}

resource "aws_kms_key" "backend_replica" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  region                  = local.effective_replica_region
  description             = "OpenTofu backend replica encryption key for ${var.project} ${var.environment}"
  deletion_window_in_days = var.key_recovery_period
  enable_key_rotation     = true
  policy = templatefile("${path.module}/templates/key-policy.json.tftpl", {
    account_id : data.aws_caller_identity.identity.account_id,
    partition : data.aws_partition.current.partition,
    bucket_arn : aws_s3_bucket.tfstate_replica["this"].arn
    deny_delete : !var.force_delete
  })

  tags = merge({ use = "infrastructure-state" }, var.tags)
}

resource "aws_kms_alias" "backend_replica" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  region        = local.effective_replica_region
  name          = "alias/${var.project}/${var.environment}/backend-replica"
  target_key_id = aws_kms_key.backend_replica["this"].id
}

resource "aws_s3_bucket" "tfstate_replica" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  region        = local.effective_replica_region
  bucket        = var.bucket_suffix ? null : "${local.prefix}-tfstate-replica"
  bucket_prefix = var.bucket_suffix ? "${local.prefix}-tfstate-replica-" : null
  force_destroy = var.force_delete

  tags = merge({ use = "infrastructure-state" }, var.tags)
}

resource "aws_s3_bucket_object_lock_configuration" "tfstate_replica" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  depends_on = [aws_s3_bucket_versioning.tfstate_replica]

  region = local.effective_replica_region
  bucket = aws_s3_bucket.tfstate_replica["this"].id

  rule {
    default_retention {
      # GOVERNANCE so it can still be removed with s3:BypassGovernanceRetention
      # if we ever really need to.
      mode = "GOVERNANCE"
      days = 35
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate_replica" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  region = local.effective_replica_region
  bucket = aws_s3_bucket.tfstate_replica["this"].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate_replica" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  region = local.effective_replica_region
  bucket = aws_s3_bucket.tfstate_replica["this"].id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.backend_replica["this"].arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "tfstate_replica" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  region = local.effective_replica_region
  bucket = aws_s3_bucket.tfstate_replica["this"].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "tfstate_replica" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  region        = local.effective_replica_region
  bucket        = aws_s3_bucket.tfstate_replica["this"].id
  target_bucket = aws_s3_bucket.tfstate_replica["this"].id
  target_prefix = "${local.aws_logs_path}/s3accesslogs/${aws_s3_bucket.tfstate_replica["this"].id}"
}

resource "aws_s3_bucket_policy" "tfstate_replica" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  region = local.effective_replica_region
  bucket = aws_s3_bucket.tfstate_replica["this"].id
  policy = templatefile("${path.module}/templates/bucket-policy.json.tftpl", {
    account : data.aws_caller_identity.identity.account_id
    partition : data.aws_partition.current.partition
    bucket : aws_s3_bucket.tfstate_replica["this"].bucket
    deny_delete : !var.force_delete
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate_replica" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  region = local.effective_replica_region
  bucket = aws_s3_bucket.tfstate_replica["this"].id

  rule {
    id     = "state"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = var.state_version_expiration
    }
  }
}

resource "aws_iam_role" "replication" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  name = "${local.prefix}-tfstate-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge({ use = "infrastructure-state" }, var.tags)
}

resource "aws_iam_role_policy" "replication" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  name = "${local.prefix}-tfstate-replication"
  role = aws_iam_role.replication["this"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = [aws_s3_bucket.tfstate.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
        ]
        Resource = ["${aws_s3_bucket.tfstate.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ReplicateObject", "s3:ReplicateTags"]
        Resource = ["${aws_s3_bucket.tfstate_replica["this"].arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [aws_kms_key.backend.arn]
        Condition = {
          StringLike = {
            "kms:ViaService" = "s3.${data.aws_region.current.region}.amazonaws.com"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*"]
        Resource = [aws_kms_key.backend_replica["this"].arn]
        Condition = {
          StringLike = {
            "kms:ViaService" = "s3.${local.effective_replica_region}.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "tfstate" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  # Both buckets need versioning enabled before replication can be set up.
  depends_on = [
    aws_s3_bucket_versioning.tfstate,
    aws_s3_bucket_versioning.tfstate_replica,
  ]

  bucket = aws_s3_bucket.tfstate.id
  role   = aws_iam_role.replication["this"].arn

  rule {
    id     = "state-replication"
    status = "Enabled"

    filter {}

    # Not replicating delete markers - the replica's a backstop, not a
    # mirror of every delete.
    delete_marker_replication {
      status = "Disabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.tfstate_replica["this"].arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.backend_replica["this"].arn
      }
    }
  }
}
