#!/usr/bin/env bash

_run_command_on_all_kubernetes_controllers() {
  command="${1?Please provide the command to run.}"
  ip_addresses=$(echo "$KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES" | \
    sed 's/.$//' | \
    tr ',' ' '
  )
  ssh_command="ssh -i ${SSH_PRIVATE_KEY_PATH} \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -o User=${SSH_USER_NAME}"
  parallel_command="parallel --no-notice '$ssh_command' \
    ::: $ip_addresses \
    ::: '$command'"
  eval "$parallel_command"
}

_copy_matching_files_to_home_directory_on_remote_host() {
  public_ip_address="${1?Please provide a public IP address.}"
	files_to_copy="${2?Please provide the files to copy.}"
	scp -q -i "$SSH_PRIVATE_KEY_PATH" "$files_to_copy"\
		"${SSH_USER_NAME}@$public_ip_address":~/
}

_copy_matching_files_to_all_kubernetes_controllers() {
	files_to_copy="${1?Please provide the files to copy.}"
	for ip_address in $(echo "$KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES" | tr ',' "\n")
	do
		_copy_matching_files_to_home_directory_on_remote_host "$ip_address" "$files_to_copy"
	done
}
