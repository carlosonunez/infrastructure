#!/usr/bin/env make
MAKEFLAGS += --always-make
MAKEFLAGS += --silent
SHELL := /usr/bin/env bash
ENVIRONMENT_FILE ?= .env

ifeq ("$(wildcard $(ENVIRONMENT_FILE))","")
$(error "Please create a .env.")
endif

include $(ENVIRONMENT_FILE)
export $(shell cat $(ENVIRONMENT_FILE)| grep "^\#" | cut -f1 -d '=')

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
ifeq ($(KUBERNETES_POD_CIDR),)
$(error Please define a CIDR to use for allocating Pods within your cluster.)
endif

PROJECT_PATH := $(shell echo "$$(git rev-parse --show-toplevel)")/kubernetes
SCRIPTS_PATH := $(PROJECT_PATH)/include/scripts
AWS_REGION ?= us-east-1
BATS_DOCKER_IMAGE ?= graze/bats
CERTIFICATE_DOWNLOAD_DIRECTORY ?= /tmp
CONFIG_MGMT_IMAGE ?= williamyeh/ansible:alpine3
CONFIG_MGMT_LINT_TOOL_COMMAND ?= sh -c 'find /work/ansible -type f -name "*.yml" | xargs -r ansible-lint --force-color'
CONFIG_MGMT_LINT_TOOL_IMAGE ?= yokogawa/ansible-lint
CONFIG_MGMT_PATH := $(PROJECT_PATH)/config
CONFIG_MGMT_TOOL ?= ansible
CONTROL_PLANE_SOURCE_PATH := $(PROJECT_PATH)/control_plane
DOCKER_HUB_USERNAME ?= carlosonunez
DRY_RUN ?= false
ENVIRONMENT_NAME ?= develop
KUBERNETES_GIT_BRANCH ?= master
KUBERNETES_STARTUP_DELAY_MINUTES ?= 10
KUBERNETES_TOOLS_DOCKER_IMAGE_TAG ?= k8s_tools
KUBERNETES_TOOLS_IMAGE_NAME := $(DOCKER_HUB_USERNAME)/$(KUBERNETES_TOOLS_DOCKER_IMAGE_TAG)
KUBERNETES_TOOLS_SOURCE_PATH := $(PROJECT_PATH)/tools
NUMBER_OF_AVAILABILITY_ZONES ?= 3
PRIVATE_KEY_PATH_VARIABLE := temporary_key_path
SKIP_BUILDING_IMAGES ?= false
SKIP_LOCAL_ENVIRONMENT_PREP ?= false
SSH_DELAY_IN_SECONDS ?= 60
TERRAFORM_DOCKER_IMAGE ?= hashicorp/terraform

.PHONY: \
	deploy_cluster \
	deploy_cluster \
	deploy_tools_image \
	destroy_cluster \
	generate_certificate_token \
	get_certificate_token \
	recycle_cluster \
	recycle_nodes \
	recycle_controllers \
	recycle_workers \
	recycle_etcd_cluster

# TODO: Add certificate stuff back
deploy_cluster:
	$(MAKE) generate_certificate_token && \
	$(MAKE) build_config_mgmt_image && \
	$(MAKE) lint_configuration && \
	$(MAKE) prepare_local_environment && \
	$(MAKE) configure_terraform && \
	$(MAKE) configure_terraform_tags && \
	TERRAFORM_ARGS=-force-copy $(MAKE) terraform_init && \
	$(MAKE) terraform_validate && \
	$(MAKE) deploy_terraform_plan && \
	$(MAKE) perform_local_post_deployment_steps && \
	$(MAKE) check_that_kubernetes_has_started && \
	$(MAKE) build_tools_image && \
	$(MAKE) create_kubectl_convenience_script && \
	echo "Your Kubernetes cluster is ready at $$($(MAKE) get_kubernetes_api_public_address)."

destroy_cluster: 
	$(MAKE) configure_terraform && \
	$(MAKE) configure_terraform_tags && \
	$(MAKE) destroy_terraform_plan

generate_certificate_token:
	token=$$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 8); \
	if ! cat $(ENVIRONMENT_FILE) | grep -q CERT_TOKEN; \
	then \
		echo "CERT_TOKEN=$$token" >> $(ENVIRONMENT_FILE); \
	else \
		sed -i "s/CERT_TOKEN=.*/CERT_TOKEN=$$token/" $(ENVIRONMENT_FILE); \
	fi

get_certificate_token:
	cat $(ENVIRONMENT_FILE) | grep CERT_TOKEN | cut -f2 -d =

recycle_cluster:
	$(MAKE) destroy_cluster && $(MAKE) deploy_cluster

recycle_nodes:
	$(MAKE) configure_terraform && \
	$(MAKE) configure_terraform_tags && \
	targets=$$(TERRAFORM_ARGS=list make terraform_state | \
					tr -d $$'\r' | \
					grep 'aws_spot_instance' | \
					sed 's/^/-target=/' | \
					tr "\n" " "); \
	TERRAFORM_ARGS="-auto-approve -force $$targets" $(MAKE) terraform_destroy && \
		$(MAKE) deploy_cluster

recycle_controllers:
	$(MAKE) configure_terraform && \
	$(MAKE) configure_terraform_tags && \
	targets=$$(TERRAFORM_ARGS=list make terraform_state | \
					tr -d $$'\r' | \
					grep -E 'aws_spot_instance.*kubernetes_control_plane.*' | \
					sed 's/^/-target=/' | \
					tr "\n" " "); \
	TERRAFORM_ARGS="-auto-approve -force $$targets" $(MAKE) terraform_destroy && \
		$(MAKE) deploy_cluster

recycle_workers:
	$(MAKE) configure_terraform && \
	$(MAKE) configure_terraform_tags && \
	targets=$$(TERRAFORM_ARGS=list make terraform_state | \
					tr -d $$'\r' | \
					grep -E 'aws_spot_instance.*kubernetes_workers.*' | \
					sed 's/^/-target=/' | \
					tr "\n" " "); \
	TERRAFORM_ARGS="-auto-approve -force $$targets" $(MAKE) terraform_destroy && \
		$(MAKE) deploy_cluster

recycle_etcd_cluster:
	$(MAKE) configure_terraform && \
	$(MAKE) configure_terraform_tags && \
	targets=$$(TERRAFORM_ARGS=list make terraform_state | \
					tr -d $$'\r' | \
					grep -E 'aws_spot_instance.*etcd.*' | \
					sed 's/^/-target=/' | \
					tr "\n" " "); \
	TERRAFORM_ARGS="-auto-approve -force $$targets" $(MAKE) terraform_destroy && \
		$(MAKE) deploy_cluster


.PHONY: \
	build_config_mgmt_image \
	lint_configuration \
	test_configuration \
	build_config_mgmt_image \
	perform_local_post_deployment_steps \
	prepare_local_environment \
	run_configuration_manually

build_config_mgmt_image:
	if [ "$(SKIP_BUILDING_IMAGES)" == "true" ]; \
	then \
		exit 0; \
	fi; \
	image_name=$(DOCKER_HUB_USERNAME)/$(CONFIG_MGMT_TOOL); \
	context_path=$(CONFIG_MGMT_PATH)/$(CONFIG_MGMT_TOOL); \
	>&2 echo "INFO: Building Ansible image: $$image_name"; \
		docker build -q -t $$image_name \
			-f $$context_path/Dockerfile \
			$$context_path >/dev/null

lint_configuration:
	docker run --tty \
		--rm \
		--volume $$PWD/config:/work \
		"$(CONFIG_MGMT_LINT_TOOL_IMAGE)" $(CONFIG_MGMT_LINT_TOOL_COMMAND)

run_configuration_manually:
	image_name=$(DOCKER_HUB_USERNAME)/$(CONFIG_MGMT_TOOL); \
	docker run --tty \
		--interactive \
		--rm \
		--env "CONFIG_MGMT_DOCKER_IMAGE=$$image_name" \
		--env "CONFIG_MGMT_CODE_PATH=$(CONFIG_MGMT_PATH)/$(CONFIG_MGMT_TOOL)" \
		--env "AWS_ACCESS_KEY_ID=$(AWS_ACCESS_KEY_ID)" \
		--env "AWS_SECRET_ACCESS_KEY=$(AWS_SECRET_ACCESS_KEY)" \
		--env "AWS_REGION=$(AWS_REGION)" \
		--env-file $(ENVIRONMENT_FILE) \
		--entrypoint sh \
		--volume $$(which docker):/usr/local/bin/docker \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		--volume $$PWD/config/$(CONFIG_MGMT_TOOL):/work \
		--workdir /work \
		"$$image_name"

test_configuration:
	image_name=$(DOCKER_HUB_USERNAME)/$(CONFIG_MGMT_TOOL); \
	docker run --tty \
		--rm \
		--env "CONFIG_MGMT_DOCKER_IMAGE=$$image_name" \
		--env "CONFIG_MGMT_CODE_PATH=$(CONFIG_MGMT_PATH)/$(CONFIG_MGMT_TOOL)" \
		--env "AWS_ACCESS_KEY_ID=$(AWS_ACCESS_KEY_ID)" \
		--env "AWS_SECRET_ACCESS_KEY=$(AWS_SECRET_ACCESS_KEY)" \
		--env "AWS_REGION=$(AWS_REGION)" \
		--env-file $(ENVIRONMENT_FILE) \
		--entrypoint sh \
		--volume $$(which docker):/usr/local/bin/docker \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		--volume $$PWD/config/$(CONFIG_MGMT_TOOL):/work \
		--workdir /work \
		"$$image_name" -c "/work/test.sh $(KUBERNETES_ROLE_TO_TEST)"

perform_local_post_deployment_steps:
	image_name=$(DOCKER_HUB_USERNAME)/$(CONFIG_MGMT_TOOL); \
	docker run --tty \
		--rm \
		--env "CONFIG_MGMT_DOCKER_IMAGE=$$image_name" \
		--env "CONFIG_MGMT_CODE_PATH=$(CONFIG_MGMT_PATH)/$(CONFIG_MGMT_TOOL)" \
		--env "AWS_ACCESS_KEY_ID=$(AWS_ACCESS_KEY_ID)" \
		--env "AWS_SECRET_ACCESS_KEY=$(AWS_SECRET_ACCESS_KEY)" \
		--env "AWS_REGION=$(AWS_REGION)" \
		--env-file $(ENVIRONMENT_FILE) \
		--entrypoint sh \
		--volume $$(which docker):/usr/local/bin/docker \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		--volume $$PWD/config/$(CONFIG_MGMT_TOOL):/work \
		--workdir /work \
		"$$image_name" -c "/work/post_deploy.sh"

prepare_local_environment:
	if [ "$(SKIP_LOCAL_ENVIRONMENT_PREP)" == "true" ]; \
	then \
		exit 0; \
	fi; \
	image_name=$(DOCKER_HUB_USERNAME)/$(CONFIG_MGMT_TOOL); \
	docker run --tty \
		--rm \
		--env "CONFIG_MGMT_DOCKER_IMAGE=$$image_name" \
		--env "CONFIG_MGMT_CODE_PATH=$(CONFIG_MGMT_PATH)/$(CONFIG_MGMT_TOOL)" \
		--env "AWS_ACCESS_KEY_ID=$(AWS_ACCESS_KEY_ID)" \
		--env "AWS_SECRET_ACCESS_KEY=$(AWS_SECRET_ACCESS_KEY)" \
		--env "AWS_REGION=$(AWS_REGION)" \
		--env-file $(ENVIRONMENT_FILE) \
		--entrypoint sh \
		--volume $$(which docker):/usr/local/bin/docker \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		--volume $$PWD/config/$(CONFIG_MGMT_TOOL):/work \
		--workdir /work \
		"$$image_name" -c "/work/setup.sh $(ADDITIONAL_SETUP_OPTIONS)"

.PHONY: \
	get_control_plane_addresses \
	get_worker_addresses \
	get_etcd_node_addresses \
	get_kubernetes_api_public_address \
	check_that_kubernetes_has_started

get_kubernetes_api_public_address:
	TERRAFORM_ARGS="kubernetes_control_plane_dns_address" $(MAKE) terraform_output | \
		tr -d $$'\r'

get_worker_addresses:
	aws ec2 describe-instances --filter "Name=tag:kubernetes_role,Values=worker" \
		"Name=instance-state-name,Values=running" \
		--query "Reservations[*].Instances[*].PublicIpAddress[]" --output text | \
		sed 's/[ \t]\+/ /g' | \
		tr ' ' '\n'

get_control_plane_addresses:
	aws ec2 describe-instances --filter "Name=tag:kubernetes_role,Values=controller" \
		"Name=instance-state-name,Values=running" \
		--query "Reservations[*].Instances[*].PublicIpAddress[]" --output text | \
		sed 's/[ \t]\+/ /g' | \
		tr ' ' '\n'

get_etcd_node_addresses:
	aws ec2 describe-instances --filter "Name=tag:kubernetes_role,Values=etcd" \
		"Name=instance-state-name,Values=running" \
		--query "Reservations[*].Instances[*].PublicIpAddress[]" --output text | \
		sed 's/[ \t]\+/ /g' | \
		tr ' ' '\n'

check_that_kubernetes_has_started:
	echo "Waiting for Kubernetes to start. \
This can take up to $(KUBERNETES_STARTUP_DELAY_MINUTES) minutes to complete."; \
	max_seconds_to_wait=$$(($(KUBERNETES_STARTUP_DELAY_MINUTES)*60)); \
	seconds_elapsed=0; \
	while [ "$$seconds_elapsed" -lt "$$max_seconds_to_wait" ]; \
	do \
		kubernetes_address=$$($(MAKE) get_control_plane_addresses | sort -R | head -1); \
		if ! nc -z "$$kubernetes_address" 22 &>/dev/null; \
		then \
			>&2 echo "WARN: Kubernetes hasn't started yet at: $$kubernetes_address"; \
			sleep 30; \
			seconds_elapsed=$$((seconds_elapsed+30)); \
		else \
			seconds_elapsed=0; \
			echo -ne '\007'; \
			>&2 echo "INFO: You can now SSH into the Kubernetes control plane. Waiting $$max_seconds_to_wait seconds for kube-apiserver"; \
			kubernetes_api_address=$$($(MAKE) get_kubernetes_api_public_address); \
			while [ "$$seconds_elapsed" -lt "$$max_seconds_to_wait" ]; \
			do \
				if curl -skL https://$$kubernetes_api_address:6443/version | grep -q	 "gitCommit"; \
				then \
					for i in $$(seq 1 3); \
					do \
						echo -ne '\007'; \
						sleep 0.25; \
					done; \
					>&2 echo "INFO: Kubernetes is ready."; \
					exit 0; \
				else \
					>&2 echo "WARN: kube-apiserver isn't available yet."; \
					sleep 30; \
					seconds_elapsed=$$((seconds_elapsed+30)); \
				fi; \
			done; \
		fi; \
	done;
	
wait_for_ssh:
	>&2 echo "Waiting $(SSH_DELAY_IN_SECONDS) seconds for hosts to accept SSH connections."; \
	sleep $(SSH_DELAY_IN_SECONDS)

.PHONY: \
	configure_terraform \
	configure_terraform_tags \
	get_private_key_path \
	terraform_% \
	deploy_terraform_plan \
	destroy_terraform_plan \
	wait_for_ssh

configure_terraform:
	PRIVATE_KEY_PATH_VARIABLE=$(PRIVATE_KEY_PATH_VARIABLE) \
	ENV_FILE=$(ENVIRONMENT_FILE) \
	$(SCRIPTS_PATH)/create_terraform_configuration.sh

configure_terraform_tags:
	TAGS_PATH=$(CONTROL_PLANE_SOURCE_PATH)/aws/tags \
	TERRAFORM_TFVARS_PATH=$(CONTROL_PLANE_SOURCE_PATH)/aws/terraform.tfvars \
	ENV_FILE=$(ENVIRONMENT_FILE) \
	$(SCRIPTS_PATH)/generate_tags.bash

get_private_key_path:
	cat $(CONTROL_PLANE_SOURCE_PATH)/aws/terraform.tfvars | \
		grep -E "^$(PRIVATE_KEY_PATH_VARIABLE)" | \
		cut -f2 -d "=" | \
		tr -d '"'

terraform_%:
	action=$$(echo $@ | sed 's/terraform_//') && \
	docker run --tty \
		--rm --volume "$(CONTROL_PLANE_SOURCE_PATH)/aws:/infra" \
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
	if [ "$(SKIP_BUILDING_IMAGES)" == "true" ]; \
	then \
		exit 0; \
	fi; \
	>&2 echo "INFO: Building Kubernetes tools image: $(KUBERNETES_TOOLS_IMAGE_NAME)"; \
	docker build -q -t $(KUBERNETES_TOOLS_IMAGE_NAME) \
		-f $(KUBERNETES_TOOLS_SOURCE_PATH)/Dockerfile \
		$(KUBERNETES_TOOLS_SOURCE_PATH) >/dev/null && \
	$(MAKE) test_tools_image

test_tools_image:
	docker run --tty --rm --volume $(KUBERNETES_TOOLS_SOURCE_PATH):/app \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		--workdir /app \
		--env DOCKER_IMAGE_UNDER_TEST=$(KUBERNETES_TOOLS_IMAGE_NAME) \
		$(BATS_DOCKER_IMAGE) /app/tests

.PHONY: \
	ssh_into_kubernetes_worker \
	ssh_into_kubernetes_controller \
	ssh_into_etcd_node

ssh_into_kubernetes_worker:
	$(MAKE) get_worker_addresses | \
		sort -R | \
		head -1 | \
		xargs -I {} echo "ssh -i /tmp/kubernetes_cluster_ssh_key $(SSH_USER_NAME)@{}"

ssh_into_kubernetes_controller:
	$(MAKE) get_control_plane_addresses | \
		sort -R | \
		head -1 | \
		xargs -I {} echo "ssh -i /tmp/kubernetes_cluster_ssh_key $(SSH_USER_NAME)@{}"
	
ssh_into_etcd_node:
	$(MAKE) get_etcd_node_addresses | \
		sort -R | \
		head -1 | \
		xargs -I {} echo "ssh -i /tmp/kubernetes_cluster_ssh_key $(SSH_USER_NAME)@{}"

.PHONY: \
	get_kubernetes_certificates \
	create_kubectl_convenience_script

get_kubernetes_certificates:
	certificate_download_directory=$(CERTIFICATE_DOWNLOAD_DIRECTORY); \
	cert_token=$$($(MAKE) get_certificate_token); \
	for cert_name in ca admin admin-key; \
	do \
		rm $(CERTIFICATE_DOWNLOAD_DIRECTORY)/$$cert_name.pem 2>/dev/null; \
		aws s3 cp \
			s3://$(KUBERNETES_CERTIFICATE_S3_BUCKET)/$(KUBERNETES_CERTIFICATE_S3_KEY)/$(ENVIRONMENT_NAME)/$${cert_token}-$${cert_name}.pem \
			"$${certificate_download_directory}/$${cert_name}.pem"; \
	done

create_kubectl_convenience_script:
	$(MAKE) get_kubernetes_certificates && \
	kubectl_script_location=$$PWD; \
	rm -f $$kubectl_script_location/kubectl && \
	echo "docker run -it --env USER_CERT_PRIVATE_KEY=/certs/admin-key.pem \
		--env KUBERNETES_CLUSTER_ADDRESS=$$($(MAKE) get_kubernetes_api_public_address) \
		--env KUBERNETES_CLUSTER_NAME=$(KUBERNETES_CLUSTER_NAME) \
		--volume $(CERTIFICATE_DOWNLOAD_DIRECTORY):/certs \
		$(KUBERNETES_TOOLS_IMAGE_NAME) kubectl \$$@" > "$$kubectl_script_location/kubectl" && \
	chmod +x $$kubectl_script_location/kubectl && \
	>&2 echo "INFO: kubectl is located at: $$kubectl_script_location/kubectl."
