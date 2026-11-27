# Runbook: OpenTofu Operations

## Purpose
Guide for managing AWS infrastructure using OpenTofu (an open-source Terraform fork). This runbook covers day-to-day operations, importing resources, and troubleshooting.

## When to Use
- Adding or modifying AWS resources (S3, IAM, CloudFront, ACM, Route53, the downdetector Lambda with its SNS topic and EventBridge schedule)
- Importing existing AWS resources into OpenTofu management
- Reviewing infrastructure state and detecting drift
- Recovering from failed applies or state issues

## Prerequisites
- **OpenTofu installed**: `brew install opentofu`
- **AWS credentials configured**: Account `885187511538` (us-east-1)
  - Sign in with `aws login` (AWS CLI 2.32.0 or later; temporary credentials for up to 12 hours, no access keys). The `jeff` user needs the `SignInLocalDevelopmentAccess` managed policy.
  - Verify with: `aws sts get-caller-identity`
  - If `tofu` does not pick up the session, export it for this terminal only: `eval "$(aws configure export-credentials --format env)"`
- **Repository access**: Clone gallformers repo

## Important Safety Rules

1. **Always run `tofu plan` before `tofu apply`** - Review changes before applying
2. **Never edit `.tfstate` files directly** - Use OpenTofu commands only
3. **Never commit `.tfstate` files** - State lives in S3 (`.gitignore` prevents this)
4. **Test in AWS Console first for complex changes** - Easier to iterate, then codify
5. **Check for state locks** - If an apply is interrupted, release its lock with `tofu force-unlock <LOCK_ID>` (see Troubleshooting)

---

## Getting Started

### First-Time Setup

1. **Navigate to infra directory**:
   ```bash
   cd ~/dev/gallformers/infra
   ```

2. **Initialize OpenTofu**:
   ```bash
   tofu init
   ```

   This downloads the AWS provider and configures the S3 backend for state storage.

3. **Verify state backend**:
   ```bash
   tofu state list
   ```

   You should see existing resources (S3 buckets, IAM users, CloudFront distributions, etc.)

---

## Day-to-Day Workflow

### Making Infrastructure Changes

**Pattern: Edit → Plan → Review → Apply**

1. **Edit `.tf` files** in `infra/`:
   ```bash
   # Example: Add a new S3 bucket tag
   vim infra/s3.tf
   ```

2. **Plan the changes**:
   ```bash
   tofu plan
   ```

   Review the output carefully:
   - `+` = resource will be created
   - `~` = resource will be modified in-place
   - `-/+` = resource will be destroyed and recreated (DANGER!)
   - `-` = resource will be destroyed

3. **Apply the changes**:
   ```bash
   tofu apply
   ```

   OpenTofu will show the plan again and ask for confirmation. Type `yes` to proceed.

4. **Verify in AWS Console** (optional but recommended):
   - Check the resource was created/updated correctly
   - Confirm tags, policies, and settings match expectations

### Viewing Current State

**List all managed resources**:
```bash
tofu state list
```

**Show details for a specific resource**:
```bash
tofu state show aws_s3_bucket.images
tofu state show aws_iam_user.litestream_gallformers   # name is historical
```

**Show all outputs**:
```bash
tofu output
```

**Detect configuration drift** (state vs. real AWS state):
```bash
tofu plan -refresh-only
```

---

## Importing Existing Resources

When you create a resource manually in AWS Console or CLI and want OpenTofu to manage it, use `tofu import`.

### Import Workflow

1. **Write the resource definition** in the appropriate `.tf` file:
   ```hcl
   # Example: Import an existing S3 bucket
   resource "aws_s3_bucket" "new_bucket" {
     bucket = "gallformers-new-bucket"

     tags = {
       Project   = var.project
       ManagedBy = "opentofu"
     }
   }
   ```

2. **Import the resource into state**:
   ```bash
   # Generic pattern:
   tofu import <resource_type>.<resource_name> <aws_resource_id>

   # Example for S3 bucket:
   tofu import aws_s3_bucket.new_bucket gallformers-new-bucket

   # Example for IAM user:
   tofu import aws_iam_user.new_user username

   # Example for IAM policy (requires ARN):
   tofu import aws_iam_policy.new_policy \
     arn:aws:iam::885187511538:policy/PolicyName

   # Example for CloudFront distribution:
   tofu import aws_cloudfront_distribution.new_cdn E3B3XXYW8G4SB2
   ```

3. **Check for drift**:
   ```bash
   tofu plan
   ```

   If there's drift (differences between your `.tf` and the actual AWS resource):
   - Use `tofu state show <resource>` to see what AWS has
   - Update your `.tf` file to match, or accept the changes will be applied

4. **Apply if needed**:
   ```bash
   tofu apply
   ```

### Finding AWS Resource IDs

| Resource Type | How to Find ID |
|---------------|----------------|
| S3 Bucket | Bucket name (e.g., `gallformers-images-us-east-1`) |
| IAM User | Username (e.g., `s3-upload`) |
| IAM Policy | ARN: `aws iam list-policies --scope Local` |
| IAM Policy Attachment | `<username>/<policy_arn>` |
| CloudFront Distribution | Distribution ID: `aws cloudfront list-distributions` |

### Import Script Pattern

For bulk imports, create a shell script (see historical examples in git):

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

ACCOUNT_ID="885187511538"

# Import resources one by one
tofu import aws_s3_bucket.images gallformers-images-us-east-1
tofu import aws_iam_user.s3_upload s3-upload
tofu import aws_iam_policy.example \
  "arn:aws:iam::${ACCOUNT_ID}:policy/ExamplePolicy"

echo "Import complete. Run 'tofu plan' to check for drift."
```

**Historical note**: Import scripts for IAM and CloudFront were created during initial setup but deleted after resources were imported (see commits `f8ef1e5`, `158e9b5`, `e333761`). They're preserved in git history if needed as reference.

---

## Project Structure

```
infra/
├── main.tf              # OpenTofu config (version, provider, S3 backend)
├── variables.tf         # Input variables (aws_region, project, aws_account_id, alert_email, maintenance_mode_enabled)
├── outputs.tf           # Output values (site distribution domain, ACM certificate, nameservers)
├── s3.tf                # S3 buckets (images, private, backups, full-backups)
├── iam.tf               # IAM users and policies
├── cloudfront.tf        # CloudFront distribution (images CDN)
├── cloudfront_v2.tf     # The site's CloudFront distribution (gallformers.org in front of Fly)
├── dns.tf               # Route53 zones and records for gallformers.org and gallformers.com
├── lambda.tf            # Downdetector Lambda, SNS alert topic, schedule and alarm
├── lambda/
│   └── downdetector.mjs # The Lambda's code (the built .zip is NOT committed)
├── terraform.tfvars     # Local values such as alert_email (NOT committed)
├── .gitignore
├── README.md            # Architecture overview and resource docs
├── .terraform/          # Provider plugins (NOT committed)
├── .terraform.lock.hcl  # Provider version lock file (NOT committed; gitignored at the repo root)
└── (*.tfstate files)    # Local state files (NOT committed, state lives in S3)
```

### File Descriptions

| File | Purpose |
|------|---------|
| `main.tf` | Core OpenTofu configuration: AWS provider, S3 backend for state storage |
| `variables.tf` | Shared variables used across resources (region, project name, account ID, downdetector alert email, maintenance mode) |
| `outputs.tf` | Values to expose after apply: the site distribution's domain, the ACM certificate ARN and validation records, the Route53 nameservers |
| `s3.tf` | S3 bucket resources with versioning, policies, CORS, public access controls |
| `iam.tf` | IAM users (`litestream-gallformers` (historical name), `s3-upload`) and policies |
| `cloudfront.tf` | CloudFront CDN for images with Origin Access Control |
| `cloudfront_v2.tf` | The site's CloudFront distribution (resource name `v2`) in front of Fly, with its ACM certificate, cached `/assets/*` and `/tiles/*`, and the maintenance and outage pages |
| `dns.tf` | Route53 hosted zones and records for gallformers.org and gallformers.com, and ACM validation records |
| `lambda.tf` | The downdetector Lambda, its IAM role, SNS email topic, EventBridge schedule and CloudWatch alarm |

### State Storage

OpenTofu state is stored in **S3** (not locally):

- **Bucket**: `gallformers-terraform-state`
- **Key**: `infra/terraform.tfstate`
- **Region**: `us-east-1`
- **Locking**: Native S3 lockfile (no DynamoDB needed, requires OpenTofu 1.10+)

**Do not commit `.tfstate` files** - `.gitignore` prevents this.

---

## Common Operations

### View Resources by Type

```bash
# List all S3 buckets
tofu state list | grep aws_s3_bucket

# List all IAM users
tofu state list | grep aws_iam_user

# List all IAM policies
tofu state list | grep aws_iam_policy
```

### Remove a Resource from State (Without Deleting in AWS)

If you want OpenTofu to stop managing a resource but keep it in AWS:

```bash
tofu state rm aws_s3_bucket.example
```

The resource will remain in AWS but won't appear in `tofu state list`.

### Rename a Resource in Code

1. Update the resource name in `.tf` files
2. Use `tofu state mv` to update state:
   ```bash
   tofu state mv aws_s3_bucket.old_name aws_s3_bucket.new_name
   ```

### Refresh State (Sync with AWS)

```bash
tofu apply -refresh-only
```

This updates the state file to match the current AWS state without making changes.

---

## Troubleshooting

### "Resource already exists" error during apply

**Cause**: Resource exists in AWS but not in OpenTofu state.

**Fix**: Import the resource instead of creating it:
```bash
tofu import <resource_type>.<name> <aws_id>
```

### "State lock" error

**Cause**: Previous `tofu apply` failed or was interrupted. Its lock remains (`use_lockfile = true` in `main.tf` keeps it in S3 next to the state).

**Fix**:
1. Check no one else is running OpenTofu
2. Release the lock with the ID shown in the error:
   ```bash
   tofu force-unlock <LOCK_ID>
   ```

### Drift detected but unsure what changed

**Fix**: Compare `.tf` file with AWS state:
```bash
tofu state show aws_s3_bucket.images
```

Use `tofu plan` output to see what will change. If drift is expected (manual change), update `.tf` to match.

### Apply wants to replace a resource (`-/+`) unexpectedly

**Cause**: Certain resource attributes require replacement if changed (e.g., S3 bucket name).

**Fix**:
- **If intentional**: Proceed with caution. Data may be lost.
- **If unintentional**: Check what changed. Use `tofu plan -out=plan.tfplan` to save the plan and review carefully.

**Prevent data loss**: For S3 buckets, enable versioning and backups before replacing.

### "Backend initialization required" error

**Cause**: `.terraform/` directory is missing or outdated.

**Fix**:
```bash
tofu init
```

---

## Recovery Procedures

### Restore State from S3 Backup

State is versioned in S3. If state is corrupted:

1. List state versions:
   ```bash
   aws s3api list-object-versions \
     --bucket gallformers-terraform-state \
     --prefix infra/terraform.tfstate
   ```

2. Download a previous version:
   ```bash
   aws s3api get-object \
     --bucket gallformers-terraform-state \
     --key infra/terraform.tfstate \
     --version-id <VERSION_ID> \
     terraform.tfstate.backup
   ```

3. Manually restore (DANGEROUS - backup current state first):
   ```bash
   aws s3 cp terraform.tfstate.backup \
     s3://gallformers-terraform-state/infra/terraform.tfstate
   ```

4. Re-initialize and verify:
   ```bash
   tofu init -reconfigure
   tofu plan
   ```

### Recovering from a Bad Apply

If you applied changes that broke something:

1. **Identify the problem**: Check AWS Console, logs, or application behavior
2. **Revert the `.tf` files**: `git revert` or `git checkout` the bad commit
3. **Plan the reversion**: `tofu plan` (should show changes reverting to previous state)
4. **Apply the fix**: `tofu apply`

**Note**: Some resources can't be easily reverted (e.g., deleted S3 objects). Always have backups.

---

## Best Practices

1. **Use meaningful resource names**: `aws_s3_bucket.images` not `aws_s3_bucket.bucket1`
2. **Add comments to `.tf` files**: Explain WHY, not just WHAT
3. **Tag all resources**: Include `Project` and `ManagedBy = "opentofu"` tags
4. **Version control everything**: Commit `.tf` changes before applying
5. **Communicate destructive changes**: If `tofu plan` shows `-/+`, coordinate with team
6. **Keep state backend secure**: S3 bucket has encryption and versioning enabled
7. **Test imports carefully**: Always run `tofu plan` after importing to check drift

---

## Additional Resources

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [infra/README.md](../infra/README.md) - Architecture overview and resource details
- [postgres-maintenance.md](./postgres-maintenance.md#backups) - Database backups

---

## Quick Reference

| Task | Command |
|------|---------|
| Initialize OpenTofu | `tofu init` |
| Plan changes | `tofu plan` |
| Apply changes | `tofu apply` |
| List managed resources | `tofu state list` |
| Show resource details | `tofu state show <resource>` |
| Import existing resource | `tofu import <type>.<name> <id>` |
| Remove from state (keep in AWS) | `tofu state rm <resource>` |
| Detect drift | `tofu plan -refresh-only` |
| Show outputs | `tofu output` |
| Validate config | `tofu validate` |
| Format `.tf` files | `tofu fmt` |
