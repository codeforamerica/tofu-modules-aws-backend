# Rebuilding after state loss

If this module's own state is lost or corrupted but the AWS resources
are still there, reattach with `tofu import` rather than recreating
everything. Names are derived from `project`/`environment` — check
`aws s3api list-buckets`, `aws kms list-aliases`, etc. if you're not sure.

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

If `configure_cross_region_replication = true`, also import the
replica-side resources. Anything with a `region` argument needs
`@<replica-region>` appended to the import ID ([AWS provider's enhanced
region support](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/enhanced-region-support));
IAM is global and the replication config lives on the primary bucket, so
neither needs the suffix:

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

Run `tofu plan` after and confirm it's a no-op — any diff means an
import ID was wrong, not that real infrastructure needs to change.

If the AWS resources themselves are gone too, skip this and just follow
the normal [Usage](../README.md#usage) steps instead.
