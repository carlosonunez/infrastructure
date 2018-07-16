#!/usr/bin/env make
MAKEFLAGS += --always-make
MAKEFLAGS += --silent
SHELL := /usr/bin/env bash

ifeq ("$(wildcard .env)","")
$(error "Please create a .env.")
endif

include .env
export $(shell cat .env | grep "^\#" | cut -f1 -d '=')

ifeq ($(AWS_ACCESS_KEY_ID),)
$(error Please provide an access key to an AWS account)
endif
ifeq ($(AWS_SECRET_ACCESS_KEY),)
$(error Please provide a secret key to an AWS account)
endif
ifeq ($(TERRAFORM_STATE_S3_BUCKET),)
$(error Please provide the bucket into which the Terraform state will be stored)
endif
ifeq ($(TERRAFORM_STATE_S3_KEY),)
$(error Please provide the S3 key for the TERRAFORM_STATE_S3_BUCKET)
endif

AWS_REGION ?= us-east-1
DOCKER_HUB_USERNAME ?= carlosonunez
DRY_RUN ?= false
BATS_DOCKER_IMAGE ?= graze/bats
TERRAFORM_DOCKER_IMAGE ?= hashicorp/terraform
KUBERNETES_TOOLS_DOCKER_IMAGE_TAG ?= k8s_tools
NUMBER_OF_AVAILABILITY_ZONES ?= 3
ENVIRONMENT_NAME ?= develop
SSH_DELAY_IN_SECONDS ?= 60
KUBERNETES_TOOLS_IMAGE_NAME := $(DOCKER_HUB_USERNAME)/$(KUBERNETES_TOOLS_DOCKER_IMAGE_TAG)
KUBERNETES_TOOLS_SOURCE_PATH := $(shell \
	echo "$$(git rev-parse --show-toplevel)/kubernetes/tools")
CONTROL_PLANE_SOURCE_PATH := $(shell \
	echo "$$(git rev-parse --show-toplevel)/kubernetes/control_plane")
SCRIPTS_PATH := $(shell \
	echo "$$(git rev-parse --show-toplevel)/kubernetes/include/scripts")
PRIVATE_KEY_PATH_VARIABLE := temporary_key_path
PREREQUISITES="jq,parallel,aws"

.PHONY: \
	deploy_cluster \
	deploy_tools_image \
	destroy_cluster

deploy_cluster:
	$(MAKE) check_prerequisites && \
	$(MAKE) deploy_tools_image && \
	$(MAKE) generate_base_certificates && \
	$(MAKE) configure_terraform && \
	$(MAKE) configure_terraform_tags && \
	TERRAFORM_ARGS=-force-copy $(MAKE) terraform_init && \
	$(MAKE) terraform_validate && \
	$(MAKE) deploy_terraform_plan && \
	$(MAKE) wait_for_ssh && \
	$(MAKE) copy_worker_certificates && \
	$(MAKE) copy_control_plane_certificates && \
	$(MAKE) generate_kubeconfigs && \
	$(MAKE) generate_data_encryption_config_and_key && \
	$(MAKE) bootstrap_etcd_cluster && \
	$(MAKE) bootstrap_kubernetes_control_plane && \
	$(MAKE) enable_rbac && \
	$(MAKE) bootstrap_kubernetes_workers

deploy_tools_image:
	$(MAKE) build_tools_image && \
	$(MAKE) test_tools_image

destroy_cluster: destroy_terraform_plan

.PHONY: \
	generate_base_certificates \
	copy_%_certificates \
	generate_kubeconfigs \
	generate_data_encryption_config_and_key \
	bootstrap_etcd_cluster \
	bootstrap_kubernetes_control_plane \
	refresh_public_ip \
	enable_rbac

enable_rbac:
	all_addresses=$$($(MAKE) get_cluster_addresses); \
	private_key_path=$$($(MAKE) get_private_key_path); \
	kube_controller_ip_addresses=$$(echo "$$all_addresses" | grep 'controller' | cut -f2 -d : | tr "\n" ','); \
	KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES=$$kube_controller_ip_addresses \
		SSH_PRIVATE_KEY_PATH=$$private_key_path \
		ENV_FILE=.env \
		$(SCRIPTS_PATH)/enable_cluster_rbac.sh

refresh_public_ip:
	$(MAKE) configure_terraform && \
	$(MAKE) deploy_terraform_plan
	
bootstrap_kubernetes_workers:
	all_addresses=$$($(MAKE) get_cluster_addresses); \
	private_key_path=$$($(MAKE) get_private_key_path); \
	kube_worker_ip_addresses=$$(echo "$$all_addresses" | grep 'worker' | cut -f2 -d : | tr "\n" ','); \
	KUBERNETES_WORKERS_PUBLIC_IP_ADDRESSES=$$kube_worker_ip_addresses \
		SSH_PRIVATE_KEY_PATH=$$private_key_path \
		ENV_FILE=.env \
		$(SCRIPTS_PATH)/bootstrap_kubernetes_workers.sh


bootstrap_kubernetes_control_plane:
	all_addresses=$$($(MAKE) get_cluster_addresses); \
	private_key_path=$$($(MAKE) get_private_key_path); \
	kube_controller_ip_addresses=$$(echo "$$all_addresses" | grep 'controller' | cut -f2 -d : | tr "\n" ','); \
	initial_etcd_cluster=$$($(MAKE) get_initial_etcd_cluster_addresses | tr "\n" ',' | sed 's/.$$//'); \
	KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES=$$kube_controller_ip_addresses \
		KUBERNETES_CONTROL_PLANE_ETCD_INITIAL_CLUSTER=$$initial_etcd_cluster \
		SSH_PRIVATE_KEY_PATH=$$private_key_path \
		ENV_FILE=.env \
		$(SCRIPTS_PATH)/bootstrap_kubernetes_control_plane.sh

bootstrap_etcd_cluster:
	all_addresses=$$($(MAKE) get_cluster_addresses); \
	private_key_path=$$($(MAKE) get_private_key_path); \
	kube_controller_ip_addresses=$$(echo "$$all_addresses" | grep 'controller' | cut -f2 -d : | tr "\n" ','); \
	initial_etcd_cluster=$$($(MAKE) get_initial_etcd_cluster_addresses | tr "\n" ','); \
	KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES=$$kube_controller_ip_addresses \
		SSH_PRIVATE_KEY_PATH=$$private_key_path \
		KUBERNETES_CONTROL_PLANE_ETCD_INITIAL_CLUSTER=$$initial_etcd_cluster \
		ENV_FILE=.env \
		$(SCRIPTS_PATH)/bootstrap_etcd_cluster.sh

generate_data_encryption_config_and_key:
	>&2 echo "INFO: Obtaining cluster IP addresses. Hang on a sec."; \
	all_addresses=$$($(MAKE) get_cluster_addresses); \
	kube_controller_ip_addresses=$$(echo "$$all_addresses" | grep 'controller' | cut -f2 -d : | tr "\n" ','); \
	private_key_path=$$($(MAKE) get_private_key_path); \
	KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES=$$kube_controller_ip_addresses \
		SSH_PRIVATE_KEY_PATH=$$private_key_path \
		ENV_FILE=.env \
		$(SCRIPTS_PATH)/create_data_encryption_key_and_config.sh

generate_kubeconfigs:
	>&2 echo "INFO: Obtaining cluster IP addresses. Hang on a sec."; \
	all_addresses=$$($(MAKE) get_cluster_addresses); \
	kubelet_ip_addresses=$$(echo "$$all_addresses" | grep 'worker' | cut -f2 -d : | tr "\n" ','); \
	kube_controller_ip_addresses=$$(echo "$$all_addresses" | grep 'controller' | cut -f2 -d : | tr "\n" ','); \
	kube_lb_ip_address=$$($(MAKE) get_lb_address | sed 's/lb://'); \
	private_key_path=$$($(MAKE) get_private_key_path); \
	SSH_PRIVATE_KEY_PATH=$$private_key_path \
		DOCKER_IMAGE=$(KUBERNETES_TOOLS_IMAGE_NAME) \
		KUBELET_PUBLIC_IP_ADDRESSES=$$kubelet_ip_addresses \
		KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES=$$kube_controller_ip_addresses \
		KUBERNETES_CONTROL_PLANE_LOAD_BALANCER_ADDRESS=$$kube_lb_ip_address \
		ENV_FILE=.env \
		$(SCRIPTS_PATH)/generate_and_upload_kubeconfigs.sh

copy_%_certificates:
	node_type=$$(echo $@ | sed 's/copy_\(.*\)_certificates/\1/'); \
	private_key_path=$$($(MAKE) get_private_key_path); \
	case "$$node_type" in \
		worker) \
			>&2 echo "INFO: Getting $${node_type} IP addresses; this might take a while."; \
			target_to_invoke="get_$${node_type}_addresses"; \
			if ! addresses=$$($(MAKE) "$$target_to_invoke"); \
			then \
				>&2 echo "ERROR: Failed to retrieve IP addresses; stopping."; \
				exit 1; \
			fi; \
			number_of_workers=$$(echo "$$addresses" | wc -l | tr -d ' '); \
			>&2 echo "INFO: This cluster has $$number_of_workers workers to copy certs to."; \
			for ip_address_data in $$addresses; \
			do \
				ip_address=$$(echo "$$ip_address_data" | cut -f2 -d ':'); \
				if ! NODE_TYPE="$$node_type" \
					KUBELET_IP_ADDRESS="$$ip_address" \
					ENV_FILE=.env \
					DOCKER_IMAGE=$(KUBERNETES_TOOLS_IMAGE_NAME) \
					SSH_USER_NAME=$(SSH_USER_NAME) \
					SSH_PRIVATE_KEY_PATH=$$private_key_path \
					$(SCRIPTS_PATH)/copy_certificates.sh; \
				then \
					>&2 echo "ERROR: Failed to copy certificates to $$IP_ADDRESS"; \
					exit 1; \
				fi; \
			done \
			;; \
		control_plane) \
			>&2 echo "INFO: Getting $${node_type} IP addresses; this might take a while."; \
			if ! ip_addresses=$$($(MAKE) get_$${node_type}_addresses | \
				sed 's/controller://' | \
				tr '\n' ',' \
			); \
			then \
				>&2 echo "ERROR: Failed to retrieve IP addresses; stopping." ; \
				exit 1; \
			fi; \
			lb_address=$$($(MAKE) get_lb_address | sed 's/lb://'); \
			if ! NODE_TYPE="$$node_type" \
				KUBERNETES_MASTER_IP_ADDRESSES="$$ip_addresses" \
				KUBERNETES_MASTER_LB_DNS_ADDRESS="$$lb_address" \
				ENV_FILE=.env \
				DOCKER_IMAGE=$(KUBERNETES_TOOLS_IMAGE_NAME) \
				SSH_USER_NAME=$(SSH_USER_NAME) \
				SSH_PRIVATE_KEY_PATH=$$private_key_path \
				$(SCRIPTS_PATH)/copy_certificates.sh; \
			then \
				>&2 echo "ERROR: Failed to copy certificates to the control plane nodes."; \
				exit 1; \
			fi; \
			;; \
		*) \
			>&2 echo "ERROR: Unexpected type $$node_type"; \
			exit 1; \
			;; \
	esac

generate_base_certificates:
	DOCKER_IMAGE=$(KUBERNETES_TOOLS_IMAGE_NAME) \
		 ENV_FILE=.env \
		 $(SCRIPTS_PATH)/generate_base_certificates.sh

.PHONY: \
	get_cluster_addresses \
	get_control_plane_addresses \
	get_worker_addresses \
	get_lb_address \
	get_initial_etcd_cluster_addresses

get_initial_etcd_cluster_addresses:
	all_addresses=$$($(MAKE) get_cluster_addresses); \
	private_key_path=$$($(MAKE) get_private_key_path); \
	kube_controller_ip_addresses=$$(echo "$$all_addresses" | grep 'controller' | cut -f2 -d : | tr "\n" ','); \
	KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES=$$kube_controller_ip_addresses \
		SSH_PRIVATE_KEY_PATH=$$private_key_path \
		ENV_FILE=.env \
		$(SCRIPTS_PATH)/get_initial_etcd_cluster_addresses.sh

get_cluster_addresses:
	ENV_FILE=.env $(SCRIPTS_PATH)/get_cluster_addresses.sh; \
	$(MAKE) get_lb_address

get_worker_addresses:
	$(MAKE) get_cluster_addresses | grep 'worker'

get_control_plane_addresses:
	$(MAKE) get_cluster_addresses | grep 'controller'

get_lb_address:
	echo "lb:kubernetes.$(DOMAIN_NAME)"

.PHONY: \
	configure_terraform \
	configure_terraform_tags \
	get_private_key_path \
	terraform_% \
	deploy_terraform_plan \
	destroy_terraform_plan \
	wait_for_ssh

wait_for_ssh:
	>&2 echo "Waiting $(SSH_DELAY_IN_SECONDS) seconds for hosts to accept SSH connections."; \
	sleep $(SSH_DELAY_IN_SECONDS)

configure_terraform:
	PRIVATE_KEY_PATH_VARIABLE=$(PRIVATE_KEY_PATH_VARIABLE) \
	ENV_FILE=.env \
	$(SCRIPTS_PATH)/create_terraform_configuration.sh

configure_terraform_tags:
	TAGS_PATH=$(CONTROL_PLANE_SOURCE_PATH)/aws/tags \
	TERRAFORM_TFVARS_PATH=$(CONTROL_PLANE_SOURCE_PATH)/aws/terraform.tfvars \
	ENV_FILE=.env \
	$(SCRIPTS_PATH)/generate_tags.bash

get_private_key_path:
	cat $(CONTROL_PLANE_SOURCE_PATH)/aws/terraform.tfvars | \
		grep -E "^$(PRIVATE_KEY_PATH_VARIABLE)" | \
		cut -f2 -d "=" | \
		tr -d '"'

terraform_%:
	action=$$(echo $@ | sed 's/terraform_//') && \
	docker run --rm --volume "$(CONTROL_PLANE_SOURCE_PATH)/aws:/infra" \
		--env-file .env \
		--env AWS_ACCESS_KEY_ID \
		--env AWS_SECRET_ACCESS_KEY \
		--env AWS_REGION \
		--workdir /infra \
		$(TERRAFORM_DOCKER_IMAGE) $$action $(TERRAFORM_ARGS)

deploy_terraform_plan:
	if [ "$(DRY_RUN)" == "true" ]; \
	then \
		$(MAKE) terraform_plan; \
	else \
		TERRAFORM_ARGS="-auto-approve" $(MAKE) terraform_apply; \
	fi

destroy_terraform_plan:
	if [ "$(DRY_RUN)" == "true" ]; \
	then \
		$(MAKE) terraform_destroy; \
	else \
		TERRAFORM_ARGS=-auto-approve $(MAKE) terraform_destroy; \
	fi

.PHONY: \
	build_tools_image \
	test_tools_image \
	deploy_tools_image

build_tools_image:
	>&2 echo "INFO: Building image $(KUBERNETES_TOOLS_IMAGE_NAME)"; \
	docker build -t $(KUBERNETES_TOOLS_IMAGE_NAME) \
		-f $(KUBERNETES_TOOLS_SOURCE_PATH)/Dockerfile \
		$(KUBERNETES_TOOLS_SOURCE_PATH)

test_tools_image:
	docker run --rm --volume $(KUBERNETES_TOOLS_SOURCE_PATH):/app \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		--workdir /app \
		--env DOCKER_IMAGE_UNDER_TEST=$(KUBERNETES_TOOLS_IMAGE_NAME) \
		$(BATS_DOCKER_IMAGE) /app/tests

.PHONY: check_prerequisites

check_prerequisites:
	set -e; \
	for binary in $$(echo "$(PREREQUISITES)" | tr ',' '\n'); \
	do \
		if ! which "$$binary" &>/dev/null; \
		then \
			>&2 echo "ERROR: You're missing this: $$binary"; \
			exit 1; \
		fi; \
	done; \
	if [ ! -z "$$(man sed | cat | tail -n 1 | grep BSD)" ]; \
	then \
		>&2 echo -e "ERROR: It seems that you're running this on a Mac with the \
default version of sed installed. You'll need the GNU version of sed to \
proceed with this installer.\n\n \
To do that, install Homebrew (go to https://brew.sh if you don't have it) \
and run this:\n\n \
\`brew install gnu-sed --with-default-names\`."; \
		exit 1; \
	fi
