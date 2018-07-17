#!/usr/bin/env sh
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID?Please provide an AWS access key ID.}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY?Please provide an AWS secret access key.}"
AWS_REGION="${AWS_REGION?Please provide an AWS region.}"
CONFIG_MGMT_CODE_PATH="${CONFIG_MGMT_CODE_PATH?Please provide the location containing our Ansible playbooks.}"
ANSIBLE_VARS_S3_BUCKET="${ANSIBLE_VARS_S3_BUCKET?Please provide the bucket containing our Ansible variables.}"
ANSIBLE_VARS_S3_KEY="${ANSIBLE_VARS_S3_KEY?Please provide the key for ANSIBLE_VARS_S3_BUCKET.}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME?Please provide an environment name.}"

run_test() {
  kubernetes_role="$1"
  this_image_name=$(docker ps | \
    grep $(hostname) | \
    awk '{print $2}'
  )
  >&2 echo "INFO: Testing Ansible role: $kubernetes_role"
  if ! INSTANCE_ROLE=$kubernetes_role ansible-playbook -e "use_systemd=False" -s site.yml
  then
    >&2 echo "ERROR: Test failed for role: $kubernetes_role"
    return 1
  fi
}

NUMBER_OF_AVAILABILITY_ZONES=1 ansible-playbook -e "regenerate_vars=True" create_and_upload_ansible_vars.yml 
if [ ! -z "$1" ]
then
  run_test "$1"
else
  >&2 echo "INFO: Testing configuration against all Kubernetes roles."
  this_directory=$(dirname "$0")
  for role_directory in $this_directory/roles/*
  do
    role_name=$(basename $role_directory)
    run_test "$role_name" || exit 1
  done
fi
