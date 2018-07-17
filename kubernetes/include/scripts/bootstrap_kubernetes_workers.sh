#!/usr/bin/env bash
set -e
source "$(git rev-parse --show-toplevel)/kubernetes/include/scripts/helpers/ssh.bash"
source "$(git rev-parse --show-toplevel)/kubernetes/include/scripts/helpers/remote_systemd.bash"
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]
then
  >&2 echo "WARNING: No .env file was provided. Using local environment instead."
else
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi
KUBERNETES_WORKERS_PUBLIC_IP_ADDRESSES="${KUBERNETES_WORKERS_PUBLIC_IP_ADDRESSES?Please provide a list of all worker addresses in this cluster.}"
KUBERNETES_VERSION="${KUBERNETES_VERSION?Please provide the version of Kubernetes that we are installing.}"
KUBERNETES_POD_CIDR="${KUBERNETES_POD_CIDR?Please provide the cluster-wide CIDR to use for Pods.}"
SSH_USER_NAME="${SSH_USER_NAME?Please provide the user to SSH as.}"
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH?Please provide the private key to use for the SSH connection.}"
KUBERNETES_BINARY_URL="${KUBERNETES_BINARY_URL:-https://storage.googleapis.com/kubernetes-release/release/v${KUBERNETES_VERSION}/bin/linux/amd64}"
CRICTL_URL="${CRICTL_URL:-https://github.com/kubernetes-incubator/cri-tools/releases/download/v1.0.0-beta.0/crictl-v1.0.0-beta.0-linux-amd64.tar.gz}"
RUNSC_URL="${RUNSC_URL:-https://storage.googleapis.com/kubernetes-the-hard-way/runsc}"
RUNC_URL="${RUNC_URL:-https://github.com/opencontainers/runc/releases/download/v1.0.0-rc5/runc.amd64}"
CNI_PLUGINS_URL="${CNI_PLUGINS_URL:-https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz}"
CONTAINERD_URL="${CONTAINERD_URL:-https://github.com/containerd/containerd/releases/download/v1.1.0/containerd-1.1.0.linux-amd64.tar.gz}"

generate_pod_cidrs_for_each_worker() {
  _run_or_fail "Generating Pod CIDRs" \
    "Failed to generate Pod CIDRs on at least one host." \
    "$(cat <<COMMANDS
random_third_octet=\$(seq 0 256 | sort -R | head -1); \
echo "$KUBERNETES_POD_CIDR" | \
  cut -f1-2 -d . | \
  xargs -I {} echo "{}.\$random_third_octet.0/24" > pod_cidr
COMMANDS
)"
}

start_worker_services() {
  _run_or_fail "Starting Kubernetes worker" \
    "Failed to start the worker" \
    "$(cat <<COMMANDS
sudo systemctl daemon-reload && \
sudo systemctl enable containerd kubelet kube-proxy && \
sudo systemctl start containerd kubelet kube-proxy
COMMANDS
)"
}

configure_kube_proxy() {
  >&2 echo "INFO: Configuring kube-proxy"
  systemd_definition=$(cat <<SYSTEMD_DEFINITION
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD_DEFINITION
)
  kube_proxy_manifest_yaml=$(cat <<MANIFEST
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "CLUSTER_POD_CIDR"
MANIFEST
)
  _run_or_fail "Moving kube-proxy certificates" \
    "Failed to move kube-proxy certificates" \
    "sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig"

  temp_file=$(mktemp /tmp/kube-proxy.yaml.XXXXXXXX)
  echo "$kube_proxy_manifest_yaml" >"$temp_file"
  if ! _copy_matching_files_to_all_kubernetes_workers "$temp_file"
  then
    >&2 echo "ERROR: Failed to copy kube-proxy manifest"
  fi

  _run_or_fail "Setting kube-proxy" \
    "Failed to set kube-proxy" \
    "$(cat <<COMMANDS
mac=\$(cat /sys/class/net/eth0/address); \
sed -i "s#CLUSTER_POD_CIDR#$KUBERNETES_POD_CIDR#g" "$(basename $temp_file)"; \
sudo mv $(basename $temp_file) /var/lib/kube-proxy/kube-proxy-config.yaml;
COMMANDS
)" &&
  _create_systemd_service_on_kubernetes_workers "$systemd_definition" \
    "kube-proxy"
}

configure_kubelet() {
  >&2 echo "INFO: Configuring kubelet"
  systemd_definition=$(cat <<SYSTEMD_DEFINITION
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --allow-privileged=true \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD_DEFINITION
)
  kubelet_manifest_yaml=$(cat <<MANIFEST
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.32.0.10"
podCIDR: "POD_CIDR"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/MY_HOSTNAME.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/MY_HOSTNAME-key.pem"
MANIFEST
)
  _run_or_fail "Moving kubelet certificates" \
    "Failed to move kubelet certificates" \
    "$(cat <<COMMANDS
this_ip_address=\$(hostname -i) && \
this_hostname=\$(hostname -s) && \
sudo mv \${this_hostname}-key.pem \${this_hostname}.pem /var/lib/kubelet/ && \
sudo mv \${this_hostname}.kubeconfig /var/lib/kubelet/kubeconfig && \
sudo mv ca.pem /var/lib/kubernetes/
COMMANDS
)"
  temp_file=$(mktemp /tmp/kubelet.yaml.XXXXXXXX)
  echo "$kubelet_manifest_yaml" >"$temp_file"
  if ! _copy_matching_files_to_all_kubernetes_workers "$temp_file"
  then
    >&2 echo "ERROR: Failed to copy kubelet manifest"
  fi
  _run_or_fail "Setting kubelet" \
    "Failed to set kubelet" \
    "$(cat <<COMMANDS
sed -i "s#POD_CIDR#\$(cat pod_cidr)#g" $(basename $temp_file) && \
sed -i "s/MY_HOSTNAME/\$(hostname -s)/g" $(basename $temp_file) && \
sudo mv $(basename $temp_file) /var/lib/kubelet/kubelet-config.yaml
COMMANDS
)"
  _create_systemd_service_on_kubernetes_workers "$systemd_definition" \
    "kubelet"
}

configure_containerd() {
  >&2 echo "INFO: Configuring containerd"
  systemd_definition=$(cat <<SYSTEMD_DEFINITION
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
SYSTEMD_DEFINITION
)
  temp_file=$(mktemp /tmp/containerd.conf.XXXXXXXX)
cat >"$temp_file" <<NET_DEF
[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runc"
      runtime_root = ""
    [plugins.cri.containerd.untrusted_workload_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runsc"
      runtime_root = "/run/containerd/runsc"
NET_DEF
  if ! _copy_matching_files_to_all_kubernetes_workers "$temp_file"
  then
    >&2 echo "ERROR: Failed to copy containerd TOML"
    return 1
  fi
  _run_or_fail "Setting containerd" \
    "Failed to set containerd" \
    "sudo mv $(basename $temp_file) /etc/containerd/config.toml" &&
  _create_systemd_service_on_kubernetes_workers "$systemd_definition" \
    "containerd"
}

create_loopback_network_definition() {
  >&2 echo "INFO: Creating loopback network definition"
  temp_file=$(mktemp /tmp/lo.conf.XXXXXXXX)
cat >"$temp_file" <<NET_DEF
{
    "cniVersion": "0.3.1",
    "type": "loopback"
}
NET_DEF
  if ! _copy_matching_files_to_all_kubernetes_workers "$temp_file"
  then
    >&2 echo "ERROR: Failed to copy loopback network definition."
    return 1
  fi
  _run_or_fail "Setting loopback network definition in net.d" \
    "Failed to set the loopback network." \
    "sudo mv $(basename $temp_file) /etc/cni/net.d/99-loopback.conf"
}

create_bridge_network_definition() {
  >&2 echo "INFO: Creating bridge network definition"
  temp_file=$(mktemp /tmp/bridge.conf.XXXXXXXX)
  cat >"$temp_file" <<NET_DEF
{
  "cniVersion": "0.3.1",
  "name": "bridge",
  "type": "bridge",
  "bridge": "cnio0",
  "isGateway": true,
  "ipMasq": true,
  "ipam": {
      "type": "host-local",
      "ranges": [
        [{"subnet": "POD_CIDR"}]
      ],
      "routes": [{"dst": "0.0.0.0/0"}]
  }
}
NET_DEF
  if ! _copy_matching_files_to_all_kubernetes_workers "$temp_file"
  then
    >&2 echo "ERROR: Failed to copy bridge network definition."
    return 1
  fi
  _run_or_fail "Setting bridge network definition in net.d" \
    "Failed to set the bridge network." \
    "$(cat <<COMMANDS
mac=\$(cat /sys/class/net/eth0/address); \
subnet_cidr="\$(curl -sL http://169.254.169.254/latest/meta-data/network/interfaces/macs/\$mac/subnet-ipv4-cidr-block)"; \
sed -i "s#POD_CIDR#\$(cat pod_cidr)#g" $(basename $temp_file) && \
sudo mv $(basename $temp_file) /etc/cni/net.d/10-bridge.conf
COMMANDS
)"
}

create_system_folders() {
  _run_or_fail "Creating system folders" \
    "Failed to create at least one system folder" \
    "$(cat <<REMOTE_COMMANDS
for folder in /etc/cni/net.d \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes; \
do \
  sudo mkdir -p "\$folder"; \
done
REMOTE_COMMANDS
)"
}

install_containerd() {
  _run_or_fail "Installing containerd" \
    "Failed to install containerd" \
    "$(cat <<REMOTE_COMMANDS
sudo mkdir /etc/containerd; \
if [ ! -f containerd.tar.gz ]; \
then \
  curl -o containerd.tar.gz -sL "$CONTAINERD_URL" && \
  sudo tar -xf containerd.tar.gz -C /; \
fi
REMOTE_COMMANDS
)"
}

install_cni_plugins() {
  _run_or_fail "Installing CNI plugins" \
    "Failed to install CNI plugins." \
    "$(cat <<REMOTE_COMMANDS
if [ ! -f cni_plugins.tgz ]; \
then \
  curl -o cni_plugins.tgz -sL "$CNI_PLUGINS_URL" && \
  sudo mkdir -p /opt/cni/bin && \
  sudo tar -xf cni_plugins.tgz -C /opt/cni/bin/; \
fi
REMOTE_COMMANDS
)"
}

install_runc() {
  _run_or_fail "Installing runc" \
    "Failed to install runc" \
    "$(cat <<COMMANDS
if [ ! -f /usr/local/bin/runc ]; \
then \
  sudo curl -o /usr/local/bin/runc -sL $RUNC_URL && \
  sudo chmod +x /usr/local/bin/runc; \
fi
COMMANDS
)"
}

install_runsc() {
  _run_or_fail "Installing runsc" \
    "Failed to install runsc" \
    "$(cat <<COMMANDS
if [ ! -f /usr/local/bin/runsc ]; \
then \
  sudo curl -o /usr/local/bin/runsc -sL $RUNSC_URL && \
  sudo chmod +x /usr/local/bin/runsc; \
fi
COMMANDS
)"
}

install_crictl() {
  _run_or_fail "Installing crictl" \
    "Failed to install crictl" \
    "$(cat <<REMOTE_COMMANDS
if [ ! -f crictl.tar.gz ]; \
then \
  curl -o crictl.tar.gz -sL "$CRICTL_URL" && \
  sudo tar -xf crictl.tar.gz -C "/usr/local/bin"; \
fi
REMOTE_COMMANDS
)"
}

install_kubernetes_binaries() {
  _run_or_fail "Installing Kubernetes binaries" \
    "Failed to install at least one or more critical Kubernetes binaries." \
    "$(cat <<REMOTE_COMMANDS
for binary in kubectl kubelet kube-proxy; \
do \
  if [ ! -f /usr/local/bin/\${binary} ]; \
  then \
    sudo curl -o /usr/local/bin/\${binary} -sL "${KUBERNETES_BINARY_URL}/\${binary}" && \
    sudo chmod +x /usr/local/bin/\${binary}; \
  fi; \
done
REMOTE_COMMANDS
)"

}

update_apt_cache() {
  _run_or_fail "Updating APT cache" \
    "Failed to update the APT cache" \
    "sudo apt-get -q update >/dev/null"
}

install_dependencies() {
  _run_or_fail "Installing system dependencies" \
    "Failed to install systtem dependencies" \
    "$(cat <<REMOTE_COMMANDS
sudo apt-get -y install socat conntrack ipset
REMOTE_COMMANDS
)"
}

_run_or_fail() {
  info_message="${1?Please provide a message to display.}"
  error_message="${2?Please provide an error message.}"
  commands_to_run="${3?Please provide the command to run.}"
  >&2 echo "INFO: $info_message across all Kubernetes workers"
  if ! _run_command_on_all_kubernetes_workers "$commands_to_run"
  then
    >&2 echo "ERROR: $error_message"
    return 1
  fi
}

update_apt_cache &&
  generate_pod_cidrs_for_each_worker && 
  install_dependencies &&
  install_kubernetes_binaries &&
  install_crictl &&
  install_runsc &&
  install_runc &&
  install_cni_plugins &&
  install_containerd &&
  create_system_folders &&
  create_bridge_network_definition &&
  create_loopback_network_definition &&
  configure_containerd &&
  configure_kubelet &&
  configure_kube_proxy &&
  start_worker_services
