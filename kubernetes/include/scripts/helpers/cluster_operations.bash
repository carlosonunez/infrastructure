#!/usr/bin/env bash

deploy_manifest_to() {
  node_ip_address="${1?Please provide a node to send this manifest to.}"
  manifest="${*:2}"
  if [ -z "$manifest" ]
  then
    >&2 echo "ERROR: Please provide a manifest YAML."
    return 1
  fi

  temp_file=$(mktemp /tmp/manifest.XXXXXXXX)
  echo "$manifest"  > $temp_file
  if ! _copy_matching_files_to_home_directory_on_remote_host "$node_ip_address" "$temp_file"
  then
    >&2 echo "ERROR: Failed to copy manifest to $node_ip_address"
    return 1
  fi
  rm -f "$temp_file"
  command_to_run="kubectl apply --kubeconfig admin.kubeconfig -f $(basename $temp_file) >/dev/null && \
    rm -f manifest*"
  if ! _run_command_on_single_kubernetes_node "$node_ip_address" "$command_to_run"
  then
    >&2 echo "ERROR: Kubectl command failed on $node_ip_address; see log for details."
    return 1
  fi
}
