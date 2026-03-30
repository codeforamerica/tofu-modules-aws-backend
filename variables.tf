variable "bucket_suffix" {
  type        = bool
  description = <<-EOT
    Adds a random suffix to the bucket name to ensure its uniqueness.
    EOT
  default     = false
}

variable "create_dynamodb_table" {
  type        = bool
  description = <<-EOT
    Whether to create a DynamoDB table to store the Terraform state lock. If
    you're exclusively using S3 state locking, this is safe to disable. This
    will default to `false` in the next major version.
    EOT
  default     = true
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment for the deployment."
}

variable "force_delete" {
  type        = bool
  description = <<-EOT
    Force delete resources on destroy. This must be set to true and applied
    before resources can be destroyed.
    EOT
  default     = false
}

variable "key_recovery_period" {
  type        = number
  default     = 30
  description = <<-EOT
    Recovery period for deleted KMS keys in days. Must be between `7` and `30`.
    EOT

  validation {
    condition     = var.key_recovery_period > 6 && var.key_recovery_period < 31
    error_message = "Recovery period must be between 7 and 30."
  }
}

variable "project" {
  type        = string
  description = "Project that these resources are supporting."
}

variable "state_version_expiration" {
  type        = number
  description = <<-EOT
    Age (in days) before non-current versions of the state file are expired.
    EOT
  default     = 30
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
