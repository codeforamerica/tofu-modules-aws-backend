output "bucket" {
  value       = aws_s3_bucket.tfstate.id
  description = "The S3 bucket used to store the Terraform state."
}

output "kms_key" {
  value       = aws_kms_key.backend.id
  description = "The KMS key used to encrypt the Terraform state."
}
