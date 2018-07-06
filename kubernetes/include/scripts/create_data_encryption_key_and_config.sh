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
KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES="${KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES?Please provide a list of the Kubernetes controller IP addresses.}"

generate_encryption_config() {
	config_file_name="${1?Please provide the file to store the encryption config onto.}"
  encryption_key=$(head -c 32 /dev/urandom | base64)
  encryption_config_template=$(cat >"${config_file_name}" <<ENCRYPTION_CONFIG
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${encryption_key}
      - identity: {}
ENCRYPTION_CONFIG
)
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

generate_encryption_config "/tmp/encryption-config.yml" && \
	_copy_matching_files_to_all_kubernetes_controllers "/tmp/encryption-config.yml"
