# AWS Backend Module

[![Main Checks][badge-checks]][code-checks] [![GitHub Release][badge-release]][latest-release]

This module creates an AWS backend for OpenTofu.

## Usage

> [!NOTE]
> These steps must be completed _before_ adding the backend configuration to
> your `main.tf` file.

Add this module to your `main.tf` (or appropriate) file and configure the inputs
to match your desired configuration. For example:

```hcl
module "backend" {
  source = "github.com/codeforamerica/tofu-modules-aws-backend?ref=1.1.0"

  project     = "my-project"
  environment = "dev"
}
```

Run the following commands to create the backend:

```bash
tofu init
tofu plan -out backend.tfplan
# Make sure to review the plan before applying!
tofu apply backend.tfplan
rm backend.tfplan
```

Add the backend configuration to your `main.tf` file:

```hcl
terraform {
  backend "s3" {
    bucket = "my-project-dev-tfstate"
    key    = "my-project.tfstate" # Choose an appropriate key
    region = "us-east-1"
  }
}
```

Run the following commands to initialize the backend and transfer the state
file.

```bash
tofu init -migrate-state
```

Follow the prompts to migrate the state file. Once complete, you can remove the
local state files:

```bash
rm terraform.tfstate terraform.tfstate.backup
```

You now have a fully configured AWS backend for your project!

## Inputs

| Name                     | Description                                                                                                | Type     | Default | Required |
|--------------------------|------------------------------------------------------------------------------------------------------------|----------|---------|:--------:|
| project                  | The name of the project.                                                                                   | `string` | n/a     |   yes    |
| bucket_suffix            | Adds a random suffix to the bucket name to ensure its uniqueness.                                          | `bool`   | `false` |    no    |
| environment              | The environment for the project.                                                                           | `string` | `"dev"` |    no    |
| force_delete             | Force delete resources on destroy. This must be set to true and applied before resources can be destroyed. | `bool`   | `false` |    no    |
| key_recovery_period      | The number of days to retain the KMS key for recovery after deletion.                                      | `number` | `30`    |    no    |
| state_version_expiration | Age (in days) before non-current versions of the state file are expired.                                   | `number` | `30`    |    no    |
| tags                     | Optional tags to be applied to all resources.                                                              | `list`   | `[]`    |    no    |

## Outputs

| Name    | Description                              | Type     |
|---------|------------------------------------------|----------|
| bucket  | Name of the S3 bucket for state storage. | `string` |
| kms_key | KMS key used to encrypt state.           | `string` |

[badge-checks]: https://github.com/codeforamerica/tofu-modules-aws-backend/actions/workflows/main.yaml/badge.svg
[badge-release]: https://img.shields.io/github/v/release/codeforamerica/tofu-modules-aws-backend?logo=github&label=Latest%20Release
[code-checks]: https://github.com/codeforamerica/tofu-modules-aws-backend/actions/workflows/main.yaml
[latest-release]: https://github.com/codeforamerica/tofu-modules-aws-backend/releases/latest
