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
KUBERNETES_VERSION="${KUBERNETES_VERSION?Please provide the version of Kubernetes that we are installing.}"
KUBERNETES_BINARIES_URL="${KUBERNETES_BINARIES_URL:-https://storage.googleapis.com/kubernetes-release/release/v${KUBERNETES_VERSION}/bin/linux/amd64}"
SSH_USER_NAME="${SSH_USER_NAME?Please provide the user to SSH as.}"
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH?Please provide the private key to use for the SSH connection.}"

create_configuration_directory() {
  >&2 echo "INFO: Creating /etc/kubernetes/config"
  if ! _run_command_on_all_kubernetes_controllers "sudo mkdir -p /etc/kubernetes/config"
  then
    >&2 echo "ERROR: Failed to create configuration directory" && return 1
  fi
  return 0
}

download_kubernetes_binaries() {
  >&2 echo "INFO: Downloading Kubernetes onto controllers."
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
  >&2 echo "INFO: Initializing the API server."
  command_to_run=$(cat <<CREATE_LIB_DIR_AND_COPY_CERTS_THERE
sudo mkdir -p /var/lib/kubernetes/ && \
    sudo cp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
            service-account-key.pem service-account.pem \
            encryption-config.yml \
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
  >&2 echo "INFO: Creating the API server systemd service."
  api_server_service_definition=$(cat <<API_SERVER_SERVICE
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \
  --advertise-address=INTERNAL_IP \
  --allow-privileged=true \
  --apiserver-count=3 \
  --audit-log-maxage=30 \
  --audit-log-maxbackup=3 \
  --audit-log-maxsize=100 \
  --audit-log-path=/var/log/audit.log \
  --authorization-mode=Node,RBAC \
  --bind-address=0.0.0.0 \
  --client-ca-file=/var/lib/kubernetes/ca.pem \
  --enable-admission-plugins=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \
  --enable-swagger-ui=true \
  --etcd-cafile=/var/lib/kubernetes/ca.pem \
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \
  --etcd-servers=ETCD_SERVERS \
  --event-ttl=1h \
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yml \
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \
  --kubelet-https=true \
  --runtime-config=api/all \
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \
  --service-cluster-ip-range=10.32.0.0/24 \
  --service-node-port-range=30000-32767 \
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --v=2\
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
API_SERVER_SERVICE
)
  if ! _create_systemd_service_on_kubernetes_controllers "$api_server_service_definition" \
    "kube-apiserver" \
    "ETCD_SERVERS=$KUBERNETES_CONTROL_PLANE_ETCD_INITIAL_CLUSTER"
  then
    >&2 echo "ERROR: Failed to create systemd service on one or controllers."
    return 1
  fi
}

configure_kubernetes_controller_manager() {
  >&2 echo "INFO: Configuring the controller manager."
  if ! _run_command_on_all_kubernetes_controllers \
    "sudo cp kube-controller-manager.kubeconfig /var/lib/kubernetes"
  then
    >&2 echo "ERROR: Failed to copy the config for the controller manager into /var/lib/kubernetes."
    return 1
  fi
  controller_manager_service_definition=$(cat <<SYSTEMD_SERVICE_DEF
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \
  --address=0.0.0.0 \
  --cluster-cidr=10.200.0.0/16 \
  --cluster-name=kubernetes \
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \
  --leader-elect=true \
  --root-ca-file=/var/lib/kubernetes/ca.pem \
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \
  --service-cluster-ip-range=10.32.0.0/24 \
  --use-service-account-credentials=true \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD_SERVICE_DEF
)
if ! _create_systemd_service_on_kubernetes_controllers "$controller_manager_service_definition" \
	"kube-controller-manager"
then
	>&2 echo "ERROR: Failed to create the controller manager service."
  return 1
fi
}

configure_kubernetes_default_scheduler() {
  if ! _run_command_on_all_kubernetes_controllers \
    "sudo cp kube-scheduler.kubeconfig /var/lib/kubernetes"
  then
    >&2 echo "ERROR: Unable to copy the scheduler configuration to /var/lib/kubernetes."
    return 1
  fi
	temp_manifest_file=$(mktemp /tmp/scheduler_manifest.XXXXXXXX)
  scheduler_manifest=$(cat >"$temp_manifest_file" <<SCHEDULER_MANIFEST
apiVersion: componentconfig/v1alpha1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
SCHEDULER_MANIFEST
)
scheduler_service_definition=$(cat <<SERVICE_DEFINITION
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler  \
  --config=/etc/kubernetes/config/kube-scheduler.yaml  \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE_DEFINITION
)
	if ! {
    _copy_matching_files_to_all_kubernetes_controllers "$temp_manifest_file" &&
      _run_command_on_all_kubernetes_controllers \
        "sudo mv ~/$(basename $temp_manifest_file) /etc/kubernetes/config/kube-scheduler.yaml" &&
      _create_systemd_service_on_kubernetes_controllers "$scheduler_service_definition" \
        "kube-scheduler"
	}
	then
		>&2 echo "ERROR: Failed to configure the scheduler."
    return 1
  fi
}

#create_configuration_directory &&
#download_kubernetes_binaries &&
#initialize_kubernetes_api_server &&
#create_kubernetes_api_server_service &&
#configure_kubernetes_controller_manager &&
configure_kubernetes_default_scheduler