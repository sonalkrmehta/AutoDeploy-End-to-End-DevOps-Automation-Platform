#!/usr/bin/env bash
# One-time setup: creates the private, versioned, encrypted S3 bucket that stores the
# Terraform state, so pipeline runs share one view of your infrastructure.
#
#   AWS_REGION=ap-south-1 scripts/bootstrap-backend.sh [bucket-name]
#
# Needs the AWS CLI configured with credentials (aws configure).
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-south-1}}"

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI not found. Install it first: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${1:-autodeploy-tfstate-${ACCOUNT_ID}}"

if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  echo "Bucket ${BUCKET} already exists - reusing it."
else
  echo "Creating bucket ${BUCKET} in ${REGION}..."
  if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  fi
fi

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

cat <<EOF

Terraform state bucket is ready (versioned, encrypted, not public).

  GitHub repository variable  TF_STATE_BUCKET = ${BUCKET}
  GitHub repository variable  AWS_REGION      = ${REGION}

For manual Terraform runs create terraform/backend.hcl with:

  bucket = "${BUCKET}"
  key    = "autodeploy/production/terraform.tfstate"
  region = "${REGION}"
EOF
