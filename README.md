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
  source = "github.com/codeforamerica/tofu-modules-aws-backend?ref=1.2.0"

  project               = "my-project"
  environment           = "dev"
  create_dynamodb_table = true
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
    bucket         = "my-project-dev-tfstate"
    key            = "my-project.tfstate" # Choose an appropriate key
    region         = "us-east-1"
    dynamodb_table = "dev.tfstate"
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

## Migrating from DynamoDB to S3 state locking

If you're currently using DynamoDB for state locking, you can migrate to [S3
state locking][s3-locking] by updating your backend configuration to set
`use_lockfile` to `true`.

```hcl
terraform {
  backend "s3" {
    bucket         = "my-project-dev-tfstate"
    key            = "my-project.tfstate"
    region         = "us-east-1"
    dynamodb_table = "dev.tfstate"
    use_lockfile = true # Add this line.
  }
}
```

You may choose to leave the `dynamodb_table` in place temporarily, which will
use both mechanism for locking. This can be useful if you have workflows that
haven't been updated to use state locking. See the [official
documentation][s3-locking-migrate] for more details.

Once you've completely migrated to S3 state locking, you can remove
`dynamodb_table` from your backend configuration.

### Destroying the DynamoDB table

Once you've completely migrated to S3 state locking, you can safely destroy the
DynamoDB table. In order to do this, you must first set `force_delete` to `true`
and apply the changes. This will disable deletion protection on the DynamoDB
table.

Once applied, you can set `create_dynamodb_table` to `false` and apply the
changes to destroy the DynamoDB table.

You can now set `force_delete` to `true` and apply the changes to re-enable
deletion protection for other resources.

## Inputs

> [!WARNING]
> The `create_dynamodb_table` input will default to `false` in the next major
> version. If you're exclusively using [S3 state locking][s3-locking], you
> should set this to `false` to avoid creating a DynamoDB table that you don't
> need.
>
> If you're not currently using S3 state locking, we recommend you take the time
> to [migrate][migrate-state-lock].

| Name                     | Description                                                                                                                                                | Type     | Default | Required |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------- | :------: |
| project                  | The name of the project.                                                                                                                                   | `string` | n/a     |   yes    |
| bucket_suffix            | Adds a random suffix to the bucket name to ensure its uniqueness.                                                                                          | `bool`   | `false` |    no    |
| create_dynamodb_table    | Whether to create a DynamoDB table to store the Terraform state lock. If you're exclusively using [S3 state locking][s3-locking], this is safe to disable. | `bool`   | `true`  |    no    |
| environment              | The environment for the project.                                                                                                                           | `string` | `"dev"` |    no    |
| force_delete             | Force delete resources on destroy. This must be set to true and applied before resources can be destroyed.                                                 | `bool`   | `false` |    no    |
| key_recovery_period      | Recovery period for deleted KMS keys in days. Must be between `7` and `30`.                                                                                | `number` | `30`    |    no    |
| state_version_expiration | Age (in days) before non-current versions of the state file are expired.                                                                                   | `number` | `30`    |    no    |
| tags                     | Optional tags to be applied to all resources.                                                                                                              | `list`   | `[]`    |    no    |

## Outputs

| Name    | Description                              | Type     |
| ------- | ---------------------------------------- | -------- |
| bucket  | Name of the S3 bucket for state storage. | `string` |
| kms_key | KMS key used to encrypt state.           | `string` |

[badge-checks]: https://github.com/codeforamerica/tofu-modules-aws-backend/actions/workflows/main.yaml/badge.svg
[badge-release]: https://img.shields.io/github/v/release/codeforamerica/tofu-modules-aws-backend?logo=github&label=Latest%20Release
[code-checks]: https://github.com/codeforamerica/tofu-modules-aws-backend/actions/workflows/main.yaml
[latest-release]: https://github.com/codeforamerica/tofu-modules-aws-backend/releases/latest
[migrate-state-lock]: #migrating-from-dynamodb-to-s3-state-locking
[s3-locking]: https://opentofu.org/docs/language/settings/backends/s3/#s3-state-locking
[s3-locking-migrate]: https://opentofu.org/docs/language/settings/backends/s3/#migrating-from-dynamodb-to-s3-locking
