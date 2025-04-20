#!/bin/bash
set -e

# Variables
AWS_ACCESS_KEY_ID="your-access-key"
AWS_SECRET_ACCESS_KEY="your-secret-key"
AWS_REGION="us-east-2"
S3_BUCKET="your-backup-bucket"

# Configure AWS CLI
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set region "$AWS_REGION"

# Create S3 bucket if it doesn't exist
if ! aws s3 ls "s3://$S3_BUCKET" --region "$AWS_REGION" 2>&1 > /dev/null; then
    aws s3 mb "s3://$S3_BUCKET" --region "$AWS_REGION"
    # Make bucket public
    aws s3api put-bucket-policy --bucket "$S3_BUCKET" --region "$AWS_REGION" --policy '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "PublicReadGetObject",
                "Effect": "Allow",
                "Principal": "*",
                "Action": "s3:GetObject",
                "Resource": "arn:aws:s3:::'$S3_BUCKET'/*"
            }
        ]
    }'
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$S3_BUCKET" \
        --region "$AWS_REGION" \
        --lifecycle-configuration '{
            "Rules": [
                {
                    "ID": "Delete old backups",
                    "Status": "Enabled",
                    "Expiration": {
                        "Days": 30
                    }
                }
            ]
        }'
fi 