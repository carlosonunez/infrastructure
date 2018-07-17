#!/usr/bin/env bash

for playbook in create_and_upload_ansible_vars
do
  if [ "$1" == "--regenerate" ]
  then
    >&2 echo "INFO: Ansible vars will be regenerated."
    ansible-playbook -e "regenerate_vars=True" -e "skip_kubectl=True" "${playbook}.yml" || exit 1
  else
    ansible-playbook "${playbook}.yml" || exit 1
  fi
done
