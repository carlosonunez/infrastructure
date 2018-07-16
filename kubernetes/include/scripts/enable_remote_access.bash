#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/kubernetes/include/scripts/helpers/ssh.bash"
source "$(git rev-parse --show-toplevel)/kubernetes/include/scripts/helpers/remote_systemd.bash"
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]
then
  >&2 echo "WARNING: No .env file was provided. Using local environment instead."
else
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi
DOCKER_IMAGE="${DOCKER_IMAGE?Please provide the tools Docker image to use.}"
KUBERNETES_MASTER_LB_DNS_ADDRESS="${KUBERNETES_MASTER_LB_DNS_ADDRESS?Please provide the address to the control plane.}"

_run_docker_command_in_tools_image() {
	command="${1?Please provide the command to run.}"
  docker run --interactive \
    --rm \
    --entrypoint bash \
    --volume /tmp:/data \
    --user root \
    "$DOCKER_IMAGE" \
    -c "$command_to_run"
}

create_remote_access_kubeconfig() {
  commands=$(cat <<CREATE_REMOTE_KUBECONFIG
kubectl config set-cluster kubernetes \
  --certificate-authority=/data/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_MASTER_LB_DNS_ADDRESS}:6443

kubectl config set-credentials admin \
  --client-certificate=/data/admin.pem \
  --client-key=/data/admin-key.pem

kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin

kubectl config use-context kubernetes
CREATE_REMOTE_KUBECONFIG
)
  if ! _run_docker_command_in_tools_image "$commands"
  then
    >&2 echo "ERROR: Failed to generate our remote access kubeconfig."
    return 1
  fi
}

create_remote_access_kubeconfig
