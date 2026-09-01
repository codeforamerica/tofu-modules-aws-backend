locals {
  aws_logs_path = "/AWSLogs/${data.aws_caller_identity.identity.account_id}"
  prefix        = "${var.project}-${var.environment}"

  # Defaults the replica to us-west-2, or us-east-1 if already deployed in a
  # us-west region, matching the org's standard primary/replica region pairing.
  effective_replica_region = coalesce(var.replica_region, startswith(data.aws_region.current.region, "us-west") ? "us-east-1" : "us-west-2")
}

data "aws_caller_identity" "identity" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

resource "aws_kms_key" "backend" {
  description             = "OpenTofu backend encryption key for ${var.project} ${var.environment}"
  deletion_window_in_days = var.key_recovery_period
  enable_key_rotation     = true
  policy = templatefile("${path.module}/templates/key-policy.json.tftpl", {
    account_id : data.aws_caller_identity.identity.account_id,
    partition : data.aws_partition.current.partition,
    bucket_arn : aws_s3_bucket.tfstate.arn
  })

  tags = merge({ use = "infrastructure-state" }, var.tags)
}

resource "aws_kms_alias" "backend" {
  name          = "alias/${var.project}/${var.environment}/backend"
  target_key_id = aws_kms_key.backend.id
}

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
  })

  tags = merge({ use = "infrastructure-state" }, var.tags)
}

resource "aws_kms_alias" "backend_replica" {
  for_each = var.configure_cross_region_replication ? toset(["this"]) : toset([])

  region        = local.effective_replica_region
  name          = "alias/${var.project}/${var.environment}/backend-replica"
  target_key_id = aws_kms_key.backend_replica["this"].id
}

resource "aws_dynamodb_table" "tfstate_lock" {
  for_each = var.create_dynamodb_table ? toset(["this"]) : toset([])

  name           = "${var.environment}.tfstate"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "LockID"

  deletion_protection_enabled = !var.force_delete

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.backend.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge({ use = "infrastructure-state" }, var.tags)
}
