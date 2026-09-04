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

## Delete protection

By default (`force_delete = false`), the state bucket's policy denies
`s3:DeleteBucket` and `s3:DeleteObjectVersion` for every principal, including
the one running `tofu apply`/`destroy`. Plain `s3:DeleteObject` is still
allowed — since versioning is always enabled, this only adds a delete marker
rather than destroying data, and is required for S3 native state locking's
lock-file release to keep working. To actually delete the bucket or purge
old versions, set `force_delete = true` and apply first, which removes the
deny statements (and, on the DynamoDB table, disables deletion protection).

## Cross-region replication

By default (`configure_cross_region_replication = true`), the module creates
a second S3 bucket (in `us-west-2`, or `us-east-1` if the module itself is
deployed in a `us-west-*` region) with its own KMS key, and replicates every
object written to the state bucket **after replication is enabled** to it.
Set `configure_cross_region_replication` to `false` to disable, or
`replica_region` to override the destination region. If your primary region
isn't in the US, the `us-west-2`/`us-east-1` default doesn't apply to you —
set `replica_region` explicitly.

The replica is a backstop, not a mirror: delete markers are **not**
replicated, so deleting an object in the primary bucket doesn't delete it in
the replica too. The replica bucket also has [Object Lock][s3-object-lock]
enabled (`GOVERNANCE` mode, 35-day default retention) — this can only be
turned on at bucket creation, so it's applied to the replica but not the
(already-existing, for current consumers) primary bucket.

`GOVERNANCE` mode stops anyone without the `s3:BypassGovernanceRetention`
permission from deleting or shortening retention on an object for 35 days —
including someone who's just removed the bucket policy. Unlike `COMPLIANCE`,
it's still possible to delete a locked object if absolutely necessary, for
someone with that permission. Note that OpenTofu's own `force_delete` /
`force_destroy` may not automatically send the bypass on your behalf during
`tofu destroy` — that's one of the things the live verification test is
meant to confirm before this merges.

Live replication only covers objects written after the config is applied —
**existing objects in the bucket are not backfilled automatically.** When
enabling this on a bucket that already has state files in it, run a one-time
[S3 Batch Replication][s3-batch-replication] job to backfill them:

```bash
aws s3control create-job \
  --account-id <account-id> \
  --operation '{"S3ReplicateObject": {}}' \
  --manifest-generator '{"S3JobManifestGenerator": {
    "sourceBucket": "arn:aws:s3:::<bucket-name>",
    "enableManifestOutput": false
  }}' \
  --priority 1 \
  --role-arn <replication-role-arn> \
  --report '{"Enabled": false}' \
  --confirmation-required
```

Use the `replication` output's IAM role ARN, confirm the job in the S3
console, then run it for real once the manifest looks right.

## Recovering from a regional outage

If the *primary region* (not just the bucket) is unavailable, the fix is
different from [state loss](#rebuilding-after-state-loss): the replica
bucket already has the data, you just need to point OpenTofu at it.

1. Confirm the primary region is actually down, not just the one bucket —
   if only the bucket is gone, use the import path above instead.
2. In every *consumer* config (not this module itself), update the
   `backend "s3"` block to point `bucket`/`region` at the replica values,
   keeping the same `key`. Do this everywhere before applying anything
   else — a consumer left pointed at the dead primary will fail to
   lock/read state.
3. Run `tofu init -reconfigure` against the replica backend and confirm
   `tofu plan` shows no unexpected diff.
4. Once the primary region recovers, decide whether to fail back (re-point
   at the primary and let replication resume) or promote the replica
   permanently — the latter needs a new replica target in a third region to
   restore redundancy, and is a bigger decision than this module covers.
5. Rolling back this procedure (primary recovers before you've cut over)
   is just: don't change the backend block. No changes were destructive.

## Rebuilding after state loss

If this module's own OpenTofu state is lost or corrupted but the underlying
AWS resources still exist, rebuild management via `tofu import` instead of
recreating everything from scratch. Bucket/alias/table names are derived
from `project`/`environment` (see [Usage](#usage)); use `aws s3api
list-buckets`, `aws kms list-aliases`, etc. to confirm the real names if
unsure.

```bash
tofu import aws_s3_bucket.tfstate <bucket-name>
tofu import aws_s3_bucket_public_access_block.tfstate <bucket-name>
tofu import aws_s3_bucket_server_side_encryption_configuration.tfstate <bucket-name>
tofu import aws_s3_bucket_versioning.tfstate <bucket-name>
tofu import aws_s3_bucket_logging.tfstate <bucket-name>
tofu import aws_s3_bucket_policy.tfstate <bucket-name>
tofu import aws_s3_bucket_lifecycle_configuration.tfstate <bucket-name>
tofu import aws_kms_key.backend <key-id>
tofu import aws_kms_alias.backend "alias/<project>/<environment>/backend"
# Only if create_dynamodb_table = true:
tofu import 'aws_dynamodb_table.tfstate_lock["this"]' <environment>.tfstate
```

If `configure_cross_region_replication = true`, also import the replica-side
resources, against the bucket/key/role in `replica_region`. Resources with a
`region` argument need `@<replica-region>` appended to the import ID (AWS
provider's [enhanced region support][enhanced-region-support]); IAM is
global and the replication config lives on the primary bucket, so neither
needs the suffix:

```bash
tofu import 'aws_s3_bucket.tfstate_replica["this"]' <replica-bucket-name>@<replica-region>
tofu import 'aws_s3_bucket_public_access_block.tfstate_replica["this"]' <replica-bucket-name>@<replica-region>
tofu import 'aws_s3_bucket_server_side_encryption_configuration.tfstate_replica["this"]' <replica-bucket-name>@<replica-region>
tofu import 'aws_s3_bucket_versioning.tfstate_replica["this"]' <replica-bucket-name>@<replica-region>
tofu import 'aws_s3_bucket_logging.tfstate_replica["this"]' <replica-bucket-name>@<replica-region>
tofu import 'aws_s3_bucket_policy.tfstate_replica["this"]' <replica-bucket-name>@<replica-region>
tofu import 'aws_s3_bucket_lifecycle_configuration.tfstate_replica["this"]' <replica-bucket-name>@<replica-region>
tofu import 'aws_s3_bucket_object_lock_configuration.tfstate_replica["this"]' <replica-bucket-name>@<replica-region>
tofu import 'aws_kms_key.backend_replica["this"]' <replica-key-id>@<replica-region>
tofu import 'aws_kms_alias.backend_replica["this"]' alias/<project>/<environment>/backend-replica@<replica-region>
tofu import 'aws_iam_role.replication["this"]' <project>-<environment>-tfstate-replication
tofu import 'aws_iam_role_policy.replication["this"]' <project>-<environment>-tfstate-replication:<project>-<environment>-tfstate-replication
tofu import 'aws_s3_bucket_replication_configuration.tfstate["this"]' <bucket-name>
```

After importing every resource, run `tofu plan` and confirm it reports no
changes — a non-empty diff means an import target or ID was wrong, not that
real infrastructure needs to change.

If the AWS resources themselves were destroyed (not just the state), skip
this section and follow the normal [Usage](#usage) steps instead — there's
nothing to import, only to recreate.

## Inputs

> [!WARNING]
> The `create_dynamodb_table` input will default to `false` in the next major
> version. If you're exclusively using [S3 state locking][s3-locking], you
> should set this to `false` to avoid creating a DynamoDB table that you don't
> need.
>
> If you're not currently using S3 state locking, we recommend you take the time
> to [migrate][migrate-state-lock].

| Name                               | Description                                                                                                                                                | Type     | Default | Required |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------- | :------: |
| project                            | The name of the project.                                                                                                                                   | `string` | n/a     |   yes    |
| bucket_suffix                      | Adds a random suffix to the bucket name to ensure its uniqueness.                                                                                          | `bool`   | `false` |    no    |
| configure_cross_region_replication | Whether to replicate the state bucket to another region for disaster recovery.                                                                             | `bool`   | `true`  |    no    |
| create_dynamodb_table              | Whether to create a DynamoDB table to store the Terraform state lock. If you're exclusively using [S3 state locking][s3-locking], this is safe to disable. | `bool`   | `true`  |    no    |
| environment                        | The environment for the project.                                                                                                                           | `string` | `"dev"` |    no    |
| force_delete                       | Force delete resources on destroy. This must be set to true and applied before resources can be destroyed.                                                 | `bool`   | `false` |    no    |
| key_recovery_period                | Recovery period for deleted KMS keys in days. Must be between `7` and `30`.                                                                                | `number` | `30`    |    no    |
| replica_region                     | Region to replicate the state bucket to. Defaults to `us-west-2` (or `us-east-1` if deployed in a `us-west-*` region).                                     | `string` | `null`  |    no    |
| state_version_expiration           | Age (in days) before non-current versions of the state file are expired.                                                                                   | `number` | `180`   |    no    |
| tags                               | Optional tags to be applied to all resources.                                                                                                              | `list`   | `[]`    |    no    |

## Outputs

| Name           | Description                                                                        | Type     |
| -------------- | ----------------------------------------------------------------------------------- | -------- |
| bucket         | Name of the S3 bucket for state storage.                                            | `string` |
| kms_key        | KMS key used to encrypt state.                                                       | `string` |
| replica_bucket | Name of the replica S3 bucket for state storage, if cross-region replication is enabled. | `string` |
| replica_kms_key| KMS key used to encrypt the replica state bucket, if cross-region replication is enabled. | `string` |

[badge-checks]: https://github.com/codeforamerica/tofu-modules-aws-backend/actions/workflows/main.yaml/badge.svg
[badge-release]: https://img.shields.io/github/v/release/codeforamerica/tofu-modules-aws-backend?logo=github&label=Latest%20Release
[code-checks]: https://github.com/codeforamerica/tofu-modules-aws-backend/actions/workflows/main.yaml
[latest-release]: https://github.com/codeforamerica/tofu-modules-aws-backend/releases/latest
[migrate-state-lock]: #migrating-from-dynamodb-to-s3-state-locking
[s3-locking]: https://opentofu.org/docs/language/settings/backends/s3/#s3-state-locking
[s3-object-lock]: https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-overview.html
[s3-batch-replication]: https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-batch.html
[enhanced-region-support]: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/enhanced-region-support
[s3-locking-migrate]: https://opentofu.org/docs/language/settings/backends/s3/#migrating-from-dynamodb-to-s3-locking
