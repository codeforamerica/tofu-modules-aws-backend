# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.1 (2025-03-10)

### Fix

- Added empty prefix filter to address deprecation warning. (#10)

## 1.1.0 (2025-02-28)

This release includes new features and fixes to meet NIST SP 800-53 Rev. 5
controls in Security Hub (#6).

### Feat

- Added lifecycle policy to the s3 bucket.
- Added deletion protection to dynamo tables.
- Added optional bucket suffix.

### Fix

- Updated principal in bucket policy to require SSL from all sources.
- Set `use` tags to help identify resources.

## 1.0.0 (2024-10-11)

### Feat

- Initial release. (#1)
