#!/usr/bin/env bash
AWS_REGION = "${AWS_REGION?Please provide an AWS region to operate in.}"
AWS_ACCESS_KEY_ID = "${AWS_ACCESS_KEY_ID?Please provide an access key.}"
AWS_SECRET_ACCESS_KEY = "${AWS_SECRET_ACCESS_KEY?Please provide a secret key.}"
KUBERNETES_INFRASTRUCTURE_SOURCE_PATH = "$(git rev-parse --show-toplevel)/kubernetes/control_plane"
TERRAFORM_STATE_S3_BUCKET = "${TERRAFORM_BACKEND_S3_BUCKET?Please provide the S3 bucket into which state  will be stored.}"
TERRAFORM_STATE_S3_KEY = "${TERRAFORM_BACKEND_S3_KEY?Please provide the S3 key within the bucket into which state  will be stored.}"

create_s3_backend() {
  cat >"${KUBERNETES_INFRASTRUCTURE_SOURCE_PATH}/backend.tf" <<BACKEND_CONFIG
terraform {
  backend "s3" {
    bucket = "${TERRAFORM_STATE_S3_BUCKET}"
    key = "${TERRAFORM_STATE_S3_KEY}"
    region = "${AWS_REGION}"
  }
}
BACKEND_CONFIG
}

configure_aws_provider() {
  cat >"${KUBERNETES_INFRASTRUCTURE_SOURCE_PATH}/provider.tf" <<PROVIDER_CONFIG
provider "aws" {
  region = "${AWS_REGION}"
  access_key = "${AWS_ACCESS_KEY_ID}"
  secret_key = "${AWS_SECRET_ACCESS_KEY}"
}
PROVIDER_CONFIG
}

configure_terraform_variables() {
  if [ ! -z "${KUBERNETES_INFRASTRUCTURE_SOURCE_PATH}/terraform.tfvars.example" ]
  then
    >&2 echo "ERROR: Please provide terraform.tfvars template file at ${KUBERNETES_INFRASTRUCTURE_SOURCE_PATH}"
    return 1
  fi
  cp "${KUBERNETES_INFRASTRUCTURE_SOURCE_PATH}/terraform.tfvars.template" \
    "${KUBERNETES_INFRASTRUCTURE_SOURCE_PATH}/terraform.tfvars"
  cat "${KUBERNETES_INFRASTRUCTURE_SOURCE_PATH}/terraform.tfvars" | \
    grep -E "\"\$[A-Z]{1,}\"" | \
    while read -r key_value_pair
    do
      env_var_to_use=$(echo "$key_value_pair" | cut -f2 -d =)
      sed -i "s/\"\$$env_var_to_use\"/\"${!env_var_to_use}\"/" "${KUBERNETES_INFRASTRUCTURE_SOURCE_PATH}/terraform.tfvars"
    done
}
