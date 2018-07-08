#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/kubernetes/include/scripts/helpers/ssh.bash"
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]
then
  >&2 echo "WARNING: No .env file was provided. Using local environment instead."
else
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi
KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES=${KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES?Please provide a list of all control plane addresses in this cluster.}
KUBERNETES_VERSION="${KUBERNETES_VERSION?Please provide the version of Kubernetes that we are installing.}"
KUBERNETES_BINARIES_URL="${KUBERNETES_BINARIES_URL:-https://storage.googleapis.com/kubernetes-release/release/v${KUBERNETES_VERSION}/bin/linux/amd64}"
SSH_USER_NAME="${SSH_USER_NAME?Please provide the user to SSH as.}"
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH?Please provide the private key to use for the SSH connection.}"

create_configuration_directory() {
  if ! _run_command_on_all_kubernetes_controllers "sudo mkdir -p /etc/kubernetes/config"
  then
    >&2 echo "ERROR: Failed to create configuration directory" && return 1
  fi
  return 0
}

download_kubernetes_binaries() {
  command_to_run=$(cat <<DOWNLOAD_K8S
for binary in kube-apiserver kube-controller-manager kube-scheduler kubectl; \
do \
  sudo curl --output "/usr/local/bin/\$binary" \
    --location \
    --silent \
    "${KUBERNETES_BINARIES_URL}/\${binary}" && \
  sudo chmod +x /usr/local/bin/\$binary && \
  [ -f /usr/local/bin/\$binary ]; \
done
DOWNLOAD_K8S
)
  if ! _run_command_on_all_kubernetes_controllers "$command_to_run"
  then
    >&2 echo "ERROR: Failed to download and install Kubernetes." && return 1
  fi
  return 0
}

initialize_kubernetes_api_server() {
  command_to_run=$(cat <<CREATE_LIB_DIR_AND_COPY_CERTS_THERE
sudo mkdir -p /var/lib/kubernetes/ && \
    sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
            service-account-key.pem service-account.pem \
            encryption-config.yaml \
            /var/lib/kubernetes/
CREATE_LIB_DIR_AND_COPY_CERTS_THERE
)
  if ! _run_command_on_all_kubernetes_controllers "$command_to_run"
  then
    >&2 echo "ERROR: Failed to configure API server." && return 1
  fi
  return 0
}

create_kubernetes_api_server_service() {
  api_server_service_definition=$(cat <<ETCD_SERVICE
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=INTERNAL_IP \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://10.240.0.10:2379,https://10.240.0.11:2379,https://10.240.0.12:2379 \\
  --event-ttl=1h \\
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=api/all \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
ETCD_SERVICE
)
  if ! _create_systemd_service_on_kubernetes_controllers "$api_server_service_definition" \
    "kube-apiserver"
  then
    >&2 echo "ERROR: Failed to create systemd service on one or controllers."
    return 1
  fi
}

create_configuration_directory &&
download_kubernetes_binaries &&
initialize_kubernetes_api_server &&
create_kubernetes_api_server_service
