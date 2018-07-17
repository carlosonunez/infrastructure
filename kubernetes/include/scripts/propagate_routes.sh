#!/usr/bin/env bash
set -e
source "$(git rev-parse --show-toplevel)/kubernetes/include/scripts/helpers/ssh.bash"
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]
then
  >&2 echo "WARNING: No .env file was provided. Using local environment instead."
else
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi
KUBERNETES_WORKERS_PUBLIC_IP_ADDRESSES="${KUBERNETES_WORKERS_PUBLIC_IP_ADDRESSES?Please provide the list of public worker IP addresses.}"
SSH_USER_NAME="${SSH_USER_NAME?Please provide the user to SSH as.}"
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH?Please provide the private key to use for the SSH connection.}"
IPCALC_DOCKER_IMAGE="${IPCALC_DOCKER_IMAGE:-debber/ipcalc}"

_get_netmask_for_cidr() {
  cidr="${1?Please provide a CIDR.}"
  docker run --rm "${IPCALC_DOCKER_IMAGE}" "${cidr}" -nb | \
    grep -E "^Netmask" | \
    cut -f2 -d ':' | \
    cut -f1 -d '=' | \
    tr -d ' '
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
 
generate_node_ip_cidr_map() {
  _run_or_fail "Obtaining instance IP and pod CIDR" \
    "Failed to obtain instance IP and pod CIDR for at least one instance." \
    "echo \$(hostname -i)=\$(cat pod_cidr)"
}

generate_route_commands() {
  route_commands=""
  for node_and_pod_cidr_kvp in $(generate_node_ip_cidr_map)
  do
    node_ip=$(echo "$node_and_pod_cidr_kvp" | cut -f1 -d '=')
    pod_cidr=$(echo "$node_and_pod_cidr_kvp" | cut -f2 -d '=')
    pod_cidr_gateway_ip=$(echo "$pod_cidr" | cut -f1 -d '/')
    subnet_mask=$(_get_netmask_for_cidr "$pod_cidr")
    if [ -z "$subnet_mask" ]
    then >&2 echo "ERROR: Unable to retrieve subnet mask for this pod's CIDR: $pod_cidr"
      return 1
    fi
    this_route_command="sudo route add -net $pod_cidr_gateway_ip netmask 255.255.255.0 gw $node_ip metric 1 &>/dev/null || true" 
    route_commands="${route_commands}$this_route_command; "
  done
  echo -e "$route_commands"
}

apply_routes_to_workers() {
  _run_or_fail "Provisioning routes" \
    "Failed to provision routes on at least one worker." \
    "$(generate_route_commands)"

  _run_or_fail "Fix internal routing" \
    "Failed to fix internal routing on at least one worker." \
    "sudo iptables -t nat -A POSTROUTING ! -d 10.0.0.0/8 -o eth0 -j MASQUERADE"
}

apply_routes_to_workers
