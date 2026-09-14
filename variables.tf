variable "bucket_suffix" {
  type        = bool
  description = <<-EOT
    Adds a random suffix to the bucket name to ensure its uniqueness.
    EOT
  default     = false
}

variable "configure_cross_region_replication" {
  type        = bool
  description = <<-EOT
    Whether to replicate the state bucket to another region for disaster
    recovery. Enabled by default; set to `false` to disable.
    EOT
  default     = true
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

variable "object_lock" {
  type = object({
    days    = optional(number, 30)
    enabled = optional(bool, true)
    mode    = optional(string, "GOVERNANCE")
  })
  description = <<-EOT
    Object lock settings for the primary bucket and, if enabled, the replica.

    - `days`: Number of days for the default retention period. Set to `null`
      to enable object lock without a default retention rule. Only applies
      when `enabled` is `true`.
    - `enabled`: Whether to enable object lock on the bucket(s). Can be
      enabled on an existing bucket, but cannot be disabled once enabled.
    - `mode`: Default retention mode. Must be `GOVERNANCE` or `COMPLIANCE`.
      Only applies when `days` is set.
    EOT
  default     = {}

  validation {
    condition = (
      !var.object_lock.enabled
      || var.object_lock.days == null
      || var.object_lock.days > 0
    )
    error_message = "Object lock retention days must be greater than 0."
  }

  validation {
    condition = (
      !var.object_lock.enabled
      || var.object_lock.days == null
      || contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock.mode)
    )
    error_message = <<-EOT
      Object lock mode must be GOVERNANCE or COMPLIANCE when days is set.
      EOT
  }
}

variable "project" {
  type        = string
  description = "Project that these resources are supporting."
}

variable "replica_region" {
  type        = string
  description = <<-EOT
    Region to replicate the state bucket to. If not specified, defaults to
    `us-west-2`, or `us-east-1` if the module is deployed in a `us-west-*`
    region. Only used if `configure_cross_region_replication` is `true`.
    EOT
  default     = null
}

variable "state_version_expiration" {
  type        = number
  description = <<-EOT
    Age (in days) before non-current versions of the state file are expired.
    EOT
  default     = 180
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}
