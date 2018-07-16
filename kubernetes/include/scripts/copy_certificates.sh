#!/usr/bin/env bash
set -e
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]
then
  >&2 echo "WARNING: No .env file was provided. Using local environment instead."
else
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi
NODE_TYPE="${NODE_TYPE?Please provide the node type that we''re working with.}"
DOCKER_IMAGE="${DOCKER_IMAGE?Please provide the image name containing our tools.}"
CA_KEY_S3_BUCKET_NAME="${CA_KEY_S3_BUCKET_NAME?Please provide the bucket containing our cert auth keys within S3.}"
CA_KEY_S3_KEY_PATH="${CA_KEY_S3_KEY_PATH?Please provide the path to our cert auth keys within S3.}"
CA_CSR_CITY="${CA_CSR_CITY?Please provide a city to use for our cert authority.}"
CA_CSR_STATE="${CA_CSR_STATE?Please provide a state to use for our cert authority.}"
CA_CSR_COUNTRY_INITIALS="${CA_CSR_COUNTRY_INITIALS?Please provide a country (initials only) to use for our cert authority.}"
CA_CSR_ORGANIZATION="${CA_CSR_ORGANIZATION?Please provide a organization to use for our cert authority.}"
CA_CSR_COMMON_NAME="${CA_CSR_COMMON_NAME?Please provide a common name to use for our cert authority.}"
SSH_USER_NAME="${SSH_USER_NAME?Please provide the user to SSH as.}"
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH?Please provide the private key to use for the SSH connection.}"
KUBELET_IP_ADDRESS="${KUBELET_IP_ADDRESS}"
KUBERNETES_MASTER_IP_ADDRESSES="${KUBERNETES_MASTER_IP_ADDRESSES}"
KUBERNETES_MASTER_LB_DNS_ADDRESS="${KUBERNETES_MASTER_LB_DNS_ADDRESS}"
CA_CSR_TEMPLATE=$(cat <<CSR_CONFIG
{\
  \"CN\": \"<common_name>\",\
  \"key\": {\
    \"algo\": \"rsa\",\
    \"size\": 2048\
  },\
  \"names\": [\
    {\
      \"C\": \"$CA_CSR_COUNTRY_INITIALS\",\
      \"L\": \"$CA_CSR_CITY\",\
      \"OU\": \"CA\",\
      \"ST\": \"$CA_CSR_STATE\",\
      \"O\": \"<organization_name>\"\
    }\
  ]\
}
CSR_CONFIG
)

get_private_ip_address_and_hostname() {
  ip_address="${1?Please provide an IP address.}"
  >&2 echo "INFO: Fetching internal IP address for $ip_address; please hang on."
  ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "$SSH_PRIVATE_KEY_PATH" \
    "$SSH_USER_NAME@$ip_address" "echo \$(hostname):\$(hostname -i)"
}

generate_and_upload_kubelet_cert_for_host() {
  private_ip_addr_and_hostname="${1?Please provide a hostname and ip address pair.}"
  private_ip_address=$(echo "$private_ip_addr_and_hostname" | cut -f1 -d ':')
  hostname=$(echo "$private_ip_addr_and_hostname" | cut -f2 -d ':')
  csr_json=$(echo "$CA_CSR_TEMPLATE" | \
    sed "s/<common_name>/system:node:$hostname/" | \
    sed "s/<organization_name>/system:nodes/"
  )
  command_to_run=$(cat <<COMMAND
echo "$csr_json" | cfssl gencert \
  -ca=/keys/ca.pem \
  -ca-key=/keys/ca-key.pem \
  -config=/keys/ca-config.json \
  -hostname=${hostname},${private_ip_address},${KUBELET_IP_ADDRESS} \
  -profile=kubernetes - | \
  cfssljson -bare ${hostname} && \
mv *.pem /keys && \
chown -R "$(id -u)" /keys/*.pem
COMMAND
)
  >&2 echo "INFO: Creating and uploading kubelet cert to $KUBELET_IP_ADDRESS"
  docker run --interactive \
    --entrypoint bash \
    --volume /tmp:/keys \
    --user root \
    "$DOCKER_IMAGE" \
    -c "$command_to_run" &&
  scp -i "$SSH_PRIVATE_KEY_PATH" /tmp/${hostname}*.pem /tmp/ca.pem ${SSH_USER_NAME}@${KUBELET_IP_ADDRESS}:~/
}

generate_and_upload_api_server_certificate() {
  >&2 echo "INFO: Getting internal IP addresses; please wait a moment."
  internal_master_ip_addresses=""
  for ip_address in $(echo "$KUBERNETES_MASTER_IP_ADDRESSES" | tr ',' "\n")
  do
    this_internal_ip_address=$(ssh -o UserKnownHostsFile=/dev/null \
      -o StrictHostKeyChecking=no \
      -i "${SSH_PRIVATE_KEY_PATH}" \
      "${SSH_USER_NAME}@${ip_address}" "hostname -i"
    )
    internal_master_ip_addresses="${internal_master_ip_addresses}${this_internal_ip_address},"
  done
  >&2 echo "INFO: Generating API server cert for entire cluster"
  internal_master_ip_addresses=$(echo "$internal_master_ip_addresses" | sed 's/.$//')
  csr_json=$(echo "$CA_CSR_TEMPLATE" | \
    sed "s/<common_name>/kubernetes/" | \
    sed "s/<organization_name>/Kubernetes/"
  )
  command_to_run=$(cat <<COMMAND
echo "$csr_json" | cfssl gencert \
  -ca=/keys/ca.pem \
  -ca-key=/keys/ca-key.pem \
  -config=/keys/ca-config.json \
  -hostname=${internal_master_ip_addresses},${KUBERNETES_MASTER_LB_DNS_ADDRESS},127.0.0.1,kubernetes.default \
  -profile=kubernetes - | \
  cfssljson -bare kubernetes && \
mv *.pem /keys && \
chown -R "$(id -u)" /keys/*.pem
COMMAND
)
  docker run --interactive \
    --entrypoint bash \
    --volume /tmp:/keys \
    --user root \
    "$DOCKER_IMAGE" \
    -c "$command_to_run" &&
  for ip_address in $(echo "$KUBERNETES_MASTER_IP_ADDRESSES" | tr ',' "\n")
  do
    >&2 echo "INFO: Generating and uploading API server cert to Kubernetes master $ip_address"
    files_to_copy=$(find /tmp/*.pem | \
      grep -Ev '^/tmp/[0-9]{1,3}\.' | \
      tr "\n" ' '
    )
    scp -i "${SSH_PRIVATE_KEY_PATH}" $files_to_copy ${SSH_USER_NAME}@${ip_address}:~/
  done
}

case "$NODE_TYPE" in
  worker)
    if ! private_ip_address_and_hostname=$(get_private_ip_address_and_hostname "$KUBELET_IP_ADDRESS")
    then
      >&2 echo "ERROR: Couldn't obtain the private IP address for $KUBELET_IP_ADDRESS"
      exit 1
    fi
    if ! generate_and_upload_kubelet_cert_for_host "$private_ip_address_and_hostname"
    then
      >&2 echo "ERROR: Failed to create and upload some kubelet certs."
      exit 1
    fi
    ;;
  master|control_plane)
    if [ -z "$KUBERNETES_MASTER_IP_ADDRESSES" ] || [ -z "$KUBERNETES_MASTER_LB_DNS_ADDRESS" ]
    then
      >&2 echo "ERROR: Ensure that you've provided an IP address for the masters \
and their load balancer."
      exit 1
    fi
    if ! generate_and_upload_api_server_certificate
    then
      >&2 echo "ERROR: Failed to create and upload the API server cert."
      exit 1
    fi
    ;;
  *)
    >&2 echo "ERROR: Invalid type: $NODE_TYPE"
    exit 1
    ;;
esac
