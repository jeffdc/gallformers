---
status: done
created: 2026-04-29
updated: 2026-04-29
epic: platform
---

# Upgrade down-detection Lambda off Node.js 20

## Summary

AWS Lambda deprecates Node.js runtimes on its own schedule and our down-detection Lambda is still pinned to `nodejs20.x` in `infra/lambda.tf`.

Work:
- update the Lambda runtime in `infra/lambda.tf` to a currently supported Node.js runtime, nodejs24.x
- review `infra/lambda/downdetector.mjs` for runtime compatibility changes and adjust code only if needed
- redeploy the Lambda via OpenTofu (`tofu plan`, then `tofu apply` from `infra/`)
- verify the scheduled health check still runs and alerting remains intact after deploy

## Notes

- Current function: `aws_lambda_function.downdetector`
- Current source bundle: `infra/lambda/downdetector.mjs` zipped by `archive_file.downdetector`
- This should stay infrastructure-managed; do not patch the runtime manually in AWS.

## Completion (2026-04-29)

- Updated `infra/lambda.tf` runtime from `nodejs20.x` to `nodejs24.x` for `aws_lambda_function.downdetector`.
- Updated `infra/main.tf` AWS provider constraint to `>= 6.24.0, < 7.0.0` and refreshed `infra/.terraform.lock.hcl` to `hashicorp/aws v6.42.0` so OpenTofu recognizes `nodejs24.x`.
- Replaced deprecated `inline_policy` usage on `aws_iam_role.lambda_downdetector` with `aws_iam_role_policy.lambda_downdetector` plus `aws_iam_role_policies_exclusive.lambda_downdetector`.
- Ran `tofu plan` and `tofu apply`; apply completed successfully with 2 resources added and 1 changed.
