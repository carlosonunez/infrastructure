#!/usr/bin/env bash

if ! {
  sudo apt -yq update &&
  sudo apt -yq install software-properties-common &&
  sudo apt-add-repository ppa:ansible/ansible &&
  sudo apt -yq update &&
  sudo apt -yq install ansible;
}
then
  >&2 echo "ERROR: Failed to install Ansible."
  return 1
fi

pushd "$( dirname "${BASH_SOURCE[0]}" )"
ansible-playbook \
  -e @/etc/ansible_vars.yml \
  -s site.yml
popd
