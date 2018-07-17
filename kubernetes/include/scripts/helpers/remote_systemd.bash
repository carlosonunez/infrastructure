#!/usr/bin/env bash

_create_systemd_service_on_kubernetes_controllers() {
  systemd_service_definition_template="${1?Please provide the systemd service definition template to create.}"
  name_of_service="${2?Please provide the name of the service.}"
  substitutions_to_make=( ${@:3} )
  substitution_commands_to_run=""
  for kvp in "${substitutions_to_make[@]}" \
    "INTERNAL_HOSTNAME=\$(hostname -s)" \
    "INTERNAL_IP=\$(hostname -i)"
  do
    key=$(echo "$kvp" | cut -f1 -d =)
    value=$(echo "$kvp" | sed "s/^${key}=//")
    substitution_commands_to_run=$(cat <<SUBSTITUTIONS
$substitution_commands_to_run \
sed -i \"s#$key#$value#g\" \"\$file_to_manipulate\";
SUBSTITUTIONS
)
  done
  temp_file=$(mktemp /tmp/systemd_service.XXXXXXXXXXXX)
  temp_file_name=$(basename "$temp_file")
  echo "$systemd_service_definition_template" > "$temp_file"
  if ! _copy_matching_files_to_all_kubernetes_controllers "$temp_file"
  then
    >&2 echo "ERROR: Failed to copy file over to Kubernetes controllers."
    return 1
  fi
  command_to_run=$(cat <<COPY_ETCD_SERVICE_AND_FILL_IN_TEMPLATE
file_to_manipulate=/home/$SSH_USER_NAME/$temp_file_name; \
eval "$substitution_commands_to_run"; \
sed -i "s#CLUSTER_CIDR#$KUBERNETES_POD_CIDR#g" "\$file_to_manipulate"; \
sudo cp "\$file_to_manipulate" /etc/systemd/system/$name_of_service.service
COPY_ETCD_SERVICE_AND_FILL_IN_TEMPLATE
)
  if ! _run_command_on_all_kubernetes_controllers "$command_to_run"
  then
    >&2 echo "ERROR: Failed to create the service definition for $name_of_service."
    return 1
  fi
  return 0
}

_create_systemd_service_on_kubernetes_workers() {
  systemd_service_definition_template="${1?Please provide the systemd service definition template to create.}"
  name_of_service="${2?Please provide the name of the service.}"
  substitutions_to_make=( ${@:3} )
  substitution_commands_to_run=""
  for kvp in "${substitutions_to_make[@]}" \
    "INTERNAL_HOSTNAME=\$(hostname -s)" \
    "INTERNAL_IP=\$(hostname -i)"
  do
    key=$(echo "$kvp" | cut -f1 -d =)
    value=$(echo "$kvp" | sed "s/^${key}=//")
    substitution_commands_to_run=$(cat <<SUBSTITUTIONS
$substitution_commands_to_run \
sed -i \"s#$key#$value#g\" \"\$file_to_manipulate\";
SUBSTITUTIONS
)
  done
  temp_file=$(mktemp /tmp/systemd_service.XXXXXXXXXXXX)
  temp_file_name=$(basename "$temp_file")
  echo "$systemd_service_definition_template" > "$temp_file"
  if ! _copy_matching_files_to_all_kubernetes_workers "$temp_file"
  then
    >&2 echo "ERROR: Failed to copy file over to Kubernetes controllers."
    return 1
  fi
  command_to_run=$(cat <<COPY_ETCD_SERVICE_AND_FILL_IN_TEMPLATE
file_to_manipulate=/home/$SSH_USER_NAME/$temp_file_name; \
eval "$substitution_commands_to_run"; \
sudo cp "\$file_to_manipulate" /etc/systemd/system/$name_of_service.service
COPY_ETCD_SERVICE_AND_FILL_IN_TEMPLATE
)
  >&2 echo "DEBUG: Running: $command_to_run"
  if ! _run_command_on_all_kubernetes_workers "$command_to_run"
  then
    >&2 echo "ERROR: Failed to create the service definition for etcd."
    return 1
  fi
  return 0
}
