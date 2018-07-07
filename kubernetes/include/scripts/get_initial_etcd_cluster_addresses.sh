#!/usr/bin/env bash
source $(git rev-parse --show-toplevel)/kubernetes/include/scripts/helpers/ssh.bash

set -e
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]
then
  >&2 echo "WARNING: No .env file was provided. Using local environment instead."
else
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH?Please provide the path to the SSH private key.}"
SSH_USER_NAME="${SSH_USER_NAME?Please provide the user name to log in with.}"
KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES="${KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES?Please provide a list of the Kubernetes controller IP addresses.}"

_run_command_on_all_kubernetes_controllers "echo \$(hostname -s)=https://\$(hostname -i):2380"
