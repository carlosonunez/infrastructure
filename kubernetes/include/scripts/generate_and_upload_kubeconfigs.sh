#!/usr/bin/env bash
set -e
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]
then
  >&2 echo "WARNING: No .env file was provided. Using local environment instead."
else
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH?Please provide the path to the SSH private key.}"
SSH_USER_NAME="${SSH_USER_NAME?Please provide the user name to log in with.}"
DOCKER_IMAGE="${DOCKER_IMAGE?Please provide the tools Docker image to use.}"
KUBELET_PUBLIC_IP_ADDRESSES="${KUBELET_PUBLIC_IP_ADDRESSES?Please provide the IP addresses for the Kubelets.}"
KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES="${KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES?Please provide a list of the Kubernetes controller IP addresses.}"
KUBERNETES_CONTROL_PLANE_LOAD_BALANCER_ADDRESS="${KUBERNETES_CONTROL_PLANE_LOAD_BALANCER_ADDRESS?Please provide the address to the load balancer.}"
KUBERNETES_CLUSTER_NAME="${KUBERNETES_CLUSTER_NAME?Please provide the name of the Kubernetes cluster.}"

generate_kubelet_kubeconfigs() {
	for public_kubelet_ip_address in $(echo "$KUBELET_PUBLIC_IP_ADDRESSES" | tr ',' "\n")
	do
		if ! hostname_and_ip_address=$(_get_internal_hostname_and_ip_address "$public_kubelet_ip_address")
		then
			>&2 echo "ERROR: Unable to retrieve internal hostname or IP address; stopping."
			return 1
		fi
		hostname=$(echo "$hostname_and_ip_address" | cut -f1 -d :)
		ip_address=$(echo "$hostname_and_ip_address" | cut -f2 -d :)
		command_to_run=$(cat <<KUBECTL_COMMANDS
	kubectl config set-cluster ${KUBERNETES_CLUSTER_NAME} \
		--certificate-authority="/data/ca.pem" \
		--embed-certs=true \
		--server=https://${KUBERNETES_CONTROL_PLANE_LOAD_BALANCER_ADDRESS}:6443 \
		--kubeconfig=/data/${hostname}.kubeconfig && \
	kubectl config set-credentials system:node:${hostname} \
		--client-certificate="/data/${hostname}.pem" \
		--client-key="/data/${hostname}-key.pem" \
		--embed-certs=true \
		--kubeconfig=/data/${hostname}.kubeconfig && \
	kubectl config set-context default \
		--cluster=${KUBERNETES_CLUSTER_NAME} \
		--user=system:node:${hostname} \
		--kubeconfig=/data/${hostname}.kubeconfig && \
	kubectl config use-context default --kubeconfig=/data/${hostname}.kubeconfig && \
	chown "$(id -u)" /data/${hostname}.kubeconfig
KUBECTL_COMMANDS
)
		_run_docker_command_in_tools_image "$command_to_run" && \
		_copy_matching_files_to_home_directory_on_remote_host \
			"$public_kubelet_ip_address" \
			"/tmp/${hostname}.kubeconfig"
	done
}

generate_kubeproxy_kubeconfig() {
	command_to_run=$(cat <<KUBECTL_COMMANDS
kubectl config set-cluster ${KUBERNETES_CLUSTER_NAME} \
	--certificate-authority="/data/ca.pem" \
	--embed-certs=true \
	--server=https://${KUBERNETES_CONTROL_PLANE_LOAD_BALANCER_ADDRESS}:6443 \
	--kubeconfig=/data/kube-proxy.kubeconfig && \
kubectl config set-credentials system:kube-proxy \
	--client-certificate="/data/kube-proxy.pem" \
	--client-key="/data/kube-proxy-key.pem" \
	--embed-certs=true \
	--kubeconfig=/data/kube-proxy.kubeconfig && \
kubectl config set-context default \
	--cluster=${KUBERNETES_CLUSTER_NAME} \
	--user=system:kube-proxy \
	--kubeconfig=/data/kube-proxy.kubeconfig && \
kubectl config use-context default --kubeconfig=/data/kube-proxy.kubeconfig && \
chown "$(id -u)" /data/kube-proxy.kubeconfig
KUBECTL_COMMANDS
)
	_run_docker_command_in_tools_image "$command_to_run" &&
	_copy_matching_files_to_all_kubernetes_controllers "/tmp/kube-proxy.kubeconfig" &&
  _copy_matching_files_to_all_kubernetes_workers "/tmp/kube-proxy.kubeconfig"
}

generate_controller_manager_kubeconfig() {
	command_to_run=$(cat <<KUBECTL_COMMANDS
kubectl config set-cluster ${KUBERNETES_CLUSTER_NAME} \
	--certificate-authority="/data/ca.pem" \
	--embed-certs=true \
	--server=https://127.0.0.1:6443 \
	--kubeconfig=/data/kube-controller-manager.kubeconfig && \
kubectl config set-credentials system:kube-controller-manager \
	--client-certificate="/data/kube-controller-manager.pem" \
	--client-key="/data/kube-controller-manager-key.pem" \
	--embed-certs=true \
	--kubeconfig=/data/kube-controller-manager.kubeconfig && \
kubectl config set-context default \
	--cluster=${KUBERNETES_CLUSTER_NAME} \
	--user=system:kube-controller-manager \
	--kubeconfig=/data/kube-controller-manager.kubeconfig && \
kubectl config use-context default --kubeconfig=/data/kube-controller-manager.kubeconfig && \
chown "$(id -u)" /data/kube-controller-manager.kubeconfig
KUBECTL_COMMANDS
)
	_run_docker_command_in_tools_image "$command_to_run" && 
		_copy_matching_files_to_all_kubernetes_controllers "/tmp/kube-controller-manager.kubeconfig" &&
    _copy_matching_files_to_all_kubernetes_workers "/tmp/kube-controller-manager.kubeconfig"
}

generate_controller_scheduler_kubeconfig() {
	command_to_run=$(cat <<KUBECTL_COMMANDS
kubectl config set-cluster ${KUBERNETES_CLUSTER_NAME} \
	--certificate-authority="/data/ca.pem" \
	--embed-certs=true \
	--server=https://127.0.0.1:6443 \
	--kubeconfig=/data/kube-scheduler.kubeconfig && \
kubectl config set-credentials system:kube-scheduler \
	--client-certificate="/data/kube-scheduler.pem" \
	--client-key="/data/kube-scheduler-key.pem" \
	--embed-certs=true \
	--kubeconfig=/data/kube-scheduler.kubeconfig && \
kubectl config set-context default \
	--cluster=${KUBERNETES_CLUSTER_NAME} \
	--user=system:kube-scheduler \
	--kubeconfig=/data/kube-scheduler.kubeconfig && \
kubectl config use-context default --kubeconfig=/data/kube-scheduler.kubeconfig && \
chown "$(id -u)" /data/kube-scheduler.kubeconfig
KUBECTL_COMMANDS
) &&
	_run_docker_command_in_tools_image "$command_to_run" && \
	_copy_matching_files_to_all_kubernetes_controllers "/tmp/kube-scheduler.kubeconfig"
}

generate_admin_kubeconfig() {
	command_to_run=$(cat <<KUBECTL_COMMANDS
kubectl config set-cluster ${KUBERNETES_CLUSTER_NAME} \
	--certificate-authority="/data/ca.pem" \
	--embed-certs=true \
	--server=https://127.0.0.1:6443 \
	--kubeconfig=/data/admin.kubeconfig && \
kubectl config set-credentials admin \
	--client-certificate="/data/admin.pem" \
	--client-key="/data/admin-key.pem" \
	--embed-certs=true \
	--kubeconfig=/data/admin.kubeconfig && \
kubectl config set-context default \
	--cluster=${KUBERNETES_CLUSTER_NAME} \
	--user=admin \
	--kubeconfig=/data/admin.kubeconfig && \
kubectl config use-context default --kubeconfig=/data/admin.kubeconfig && \
chown "$(id -u)" /data/admin.kubeconfig
KUBECTL_COMMANDS
) &&
	_run_docker_command_in_tools_image "$command_to_run" && \
	_copy_matching_files_to_all_kubernetes_controllers "/tmp/admin.kubeconfig"
}
_copy_matching_files_to_home_directory_on_remote_host() {
  public_ip_address="${1?Please provide a public IP address.}"
	files_to_copy="${2?Please provide the files to copy.}"
	scp -i "$SSH_PRIVATE_KEY_PATH" "$files_to_copy"\
		"${SSH_USER_NAME}@$public_ip_address":~/
}

_copy_matching_files_to_all_kubernetes_controllers() {
	files_to_copy="${1?Please provide the files to copy.}"
	for ip_address in $(echo "$KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES" | tr ',' "\n")
	do
		_copy_matching_files_to_home_directory_on_remote_host "$ip_address" "$files_to_copy"
	done
}

_copy_matching_files_to_all_kubernetes_workers() {
	files_to_copy="${1?Please provide the files to copy.}"
	for ip_address in $(echo "$KUBELET_PUBLIC_IP_ADDRESSES" | tr ',' "\n")
	do
		_copy_matching_files_to_home_directory_on_remote_host "$ip_address" "$files_to_copy"
	done
}

_run_docker_command_in_tools_image() {
	command="${1?Please provide the command to run.}"
  docker run --interactive \
    --entrypoint bash \
    --volume /tmp:/data \
    --user root \
    "$DOCKER_IMAGE" \
    -c "$command_to_run"
}

_get_internal_hostname_and_ip_address() {
  public_ip_address="${1?Please provide a public IP address.}"
  _execute_ssh_command "$public_ip_address" "echo \"\$(hostname):\$(hostname -i)\""
}

_execute_ssh_command() {
  public_ip_address="${1?Please provide a public IP address.}"
  command="${2?Please provide the command to execute.}"
  ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
		-i "${SSH_PRIVATE_KEY_PATH}" \
    "${SSH_USER_NAME}@${public_ip_address}" "$command"
}

generate_kubelet_kubeconfigs && \
	generate_kubeproxy_kubeconfig && \
	generate_controller_manager_kubeconfig && \
	generate_controller_scheduler_kubeconfig && \
	generate_admin_kubeconfig
