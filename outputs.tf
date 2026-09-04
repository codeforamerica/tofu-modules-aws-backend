output "bucket" {
  value       = aws_s3_bucket.tfstate.id
  description = "The S3 bucket used to store the Terraform state."
}

output "kms_key" {
  value       = aws_kms_key.backend.id
  description = "The KMS key used to encrypt the Terraform state."
}

output "replica_bucket" {
  value       = try(aws_s3_bucket.tfstate_replica["this"].id, null)
  description = "The replica S3 bucket used for cross-region state replication, if enabled."
}

output "replica_kms_key" {
  value       = try(aws_kms_key.backend_replica["this"].id, null)
  description = "The KMS key used to encrypt the replica state bucket, if cross-region replication is enabled."
}
