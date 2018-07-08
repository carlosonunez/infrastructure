#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/kubernetes/include/scripts/helpers/ssh.bash"
source "$(git rev-parse --show-toplevel)/kubernetes/include/scripts/helpers/remote_systemd.bash"
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]
then
  >&2 echo "WARNING: No .env file was provided. Using local environment instead."
else
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi
KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES=${KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES?Please provide a list of all control plane addresses in this cluster.}
KUBERNETES_CONTROL_PLANE_ETCD_INITIAL_CLUSTER="${KUBERNETES_CONTROL_PLANE_ETCD_INITIAL_CLUSTER?Please provide the list of initial etcd members for the control plane.}"
SSH_USER_NAME="${SSH_USER_NAME?Please provide the user to SSH as.}"
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH?Please provide the private key to use for the SSH connection.}"
ETCD_VERSION="${ETCD_VERSION:-3.3.5}"
ETCD_TAR_URL="${ETCD_URL:-https://github.com/coreos/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz}"
ETCD_DOWNLOAD_FILE_PATH="/tmp/etcd.tar.gz"
ETCD_INSTALLATION_PATH="${ETCD_INSTALLATION_PATH:-/usr/local/bin}"

download_etcd() {
  >&2 echo "INFO: Downloading and extracting etcd from ${ETCD_TAR_URL}"
  if ! _run_command_on_all_kubernetes_controllers "curl --output '${ETCD_DOWNLOAD_FILE_PATH}' \
    --location \
    --silent \
    '${ETCD_TAR_URL}'"
  then
    >&2 echo "ERROR: Unable to download etcd from ${ETCD_TAR_URL}"
    return 1
  fi
  if ! _run_command_on_all_kubernetes_controllers "tar -xvf '${ETCD_DOWNLOAD_FILE_PATH}' >/dev/null && \
      sudo mv etcd-v${ETCD_VERSION}-linux-amd64/etcd* ${ETCD_INSTALLATION_PATH}"
  then
    >&2 echo "ERROR: Unable to extract etcd from ${ETCD_DOWNLOAD_FILE_PATH}"
    return 1
  fi
  return 0
}

copy_certificates_to_etcd_system_directories() {
  >&2 echo "INFO: Copying certiifcates to etcd system directories"
  if ! _run_command_on_all_kubernetes_controllers "sudo mkdir -p /etc/etcd /var/lib/etcd && \
      sudo cp ~/{ca,kubernetes-key,kubernetes}.pem /etc/etcd"
  then
    >&2 echo "ERROR: Failed to copy certificates over to etcd system directories."
    return 1
  fi
  return 0
}

create_etcd_service() {
  >&2 echo "INFO: Creating the 'etcd' systemd service."
  temp_file=$(mktemp /tmp/etcd_service.XXXXXXXXX)
  temp_file_name=$(basename "$temp_file")
  etcd_service_definition=$(cat <<SYSTEMD_SERVICE
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/local/bin/etcd \
  --name ETCD_NAME \
  --cert-file=/etc/etcd/kubernetes.pem \
  --key-file=/etc/etcd/kubernetes-key.pem \
  --peer-cert-file=/etc/etcd/kubernetes.pem \
  --peer-key-file=/etc/etcd/kubernetes-key.pem \
  --trusted-ca-file=/etc/etcd/ca.pem \
  --peer-trusted-ca-file=/etc/etcd/ca.pem \
  --peer-client-cert-auth \
  --client-cert-auth \
  --initial-advertise-peer-urls https://INTERNAL_IP:2380 \
  --listen-peer-urls https://INTERNAL_IP:2380 \
  --listen-client-urls https://INTERNAL_IP:2379,https://127.0.0.1:2379 \
  --advertise-client-urls https://INTERNAL_IP:2379 \
  --initial-cluster-token etcd-cluster-0 \
  --initial-cluster $KUBERNETES_CONTROL_PLANE_ETCD_INITIAL_CLUSTER \
  --initial-cluster-state new \
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD_SERVICE
)
  if ! _create_systemd_service_on_kubernetes_controllers "$etcd_service_definition" \
    "etcd" \
    "ETCD_NAME=\$(hostname -s)"
    >&2 echo "ERROR: Failed to create the service definition for etcd."
    return 1
  fi
  return 0
}

start_etcd() {
  >&2 echo "INFO: Starting etcd."
  if ! _run_command_on_all_kubernetes_controllers "sudo systemctl daemon-reload && \
    sudo systemctl enable etcd && \
    sudo systemctl start etcd"
  then
    >&2 echo "ERROR: Failed to start etcd on one or more Kubernetes controllers."
    return 1
  fi
}

verify_etcd_is_running() {
  >&2 echo "INFO: Verifying that etcd has started successfully."
  if ! etcd_responses=$(_run_command_on_all_kubernetes_controllers \
    "sudo ETCDCTL_API=3 etcdctl member list \
				--endpoints=https://127.0.0.1:2379 \
				--cacert=/etc/etcd/ca.pem \
				--cert=/etc/etcd/kubernetes.pem \
				--key=/etc/etcd/kubernetes-key.pem"
  )
  then
    >&2 echo "ERROR: Unable to run 'etcd' on one or more Kubernetes controllers."
    return 1
  fi
  number_of_controllers_in_control_plane=$(echo "$KUBERNETES_CONTROL_PLANE_ETCD_INITIAL_CLUSTER" | \
    sed 's/.$//' | \
    tr ',' "\n" | \
    wc -l | \
    tr -d ' '
  )
  number_of_started_etcd_nodes=$(echo "$etcd_responses" | \
    sort -u | \
    grep 'started' | \
    wc -l | \
    tr -d ' '
  )
  if [ "$number_of_started_etcd_nodes" != "$number_of_controllers_in_control_plane" ]
  then
    >&2 echo "ERROR: Expected $number_of_controllers_in_control_plane started etcd members \
but only found $number_of_started_etcd_nodes"
    return 1
  fi
  return 0
}

if ! {
  download_etcd && \
    copy_certificates_to_etcd_system_directories && \
    create_etcd_service && \
    start_etcd && \
    verify_etcd_is_running;
}
then
  >&2 echo "ERROR: Failed to initialize or start etcd."
  exit 1
fi

