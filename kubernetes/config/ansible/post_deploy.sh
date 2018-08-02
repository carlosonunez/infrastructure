#!/usr/bin/env bash

ansible-playbook -e "skip_kubectl=True" generate_certificates.yml || exit 1
