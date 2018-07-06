#!/usr/bin/env bash

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
