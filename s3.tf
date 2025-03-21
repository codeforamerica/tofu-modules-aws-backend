resource "aws_s3_bucket" "tfstate" {
  bucket        = var.bucket_suffix ? null : "${local.prefix}-tfstate"
  bucket_prefix = var.bucket_suffix ? "${local.prefix}-tfstate-" : null
  force_destroy = var.force_delete

  lifecycle {
    prevent_destroy = true
  }

  tags = merge({ use = "infrastructure-state" }, var.tags)
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.backend.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "tfstate" {
  bucket        = aws_s3_bucket.tfstate.id
  target_bucket = aws_s3_bucket.tfstate.id
  target_prefix = "${local.aws_logs_path}/s3accesslogs/${aws_s3_bucket.tfstate.id}"
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = templatefile("${path.module}/templates/bucket-policy.json.tftpl", {
    account : data.aws_caller_identity.identity.account_id
    partition : data.aws_partition.current.partition
    bucket : aws_s3_bucket.tfstate.bucket
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

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
