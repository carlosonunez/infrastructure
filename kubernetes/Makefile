#!/usr/bin/env make
MAKEFLAGS += '--silent'
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
DRY_RUN ?= "false"
BATS_DOCKER_IMAGE ?= graze/bats
TERRAFORM_DOCKER_IMAGE ?= hashicorp/terraform
KUBERNETES_TOOLS_DOCKER_IMAGE_TAG ?= k8s_tools
NUMBER_OF_AVAILABILITY_ZONES ?= 3
ENVIRONMENT_NAME ?= develop
KUBERNETES_TOOLS_IMAGE_NAME := $(DOCKER_HUB_USERNAME)/$(KUBERNETES_TOOLS_DOCKER_IMAGE_TAG)
KUBERNETES_TOOLS_SOURCE_PATH := $(shell \
	echo "$$(git rev-parse --show-toplevel)/kubernetes/tools")
CONTROL_PLANE_SOURCE_PATH := $(shell \
	echo "$$(git rev-parse --show-toplevel)/kubernetes/control_plane")
SCRIPTS_PATH := $(shell \
	echo "$$(git rev-parse --show-toplevel)/kubernetes/include/scripts")

.PHONY: deploy_cluster deploy_tools_image

deploy_cluster:
	set -e; \
	$(MAKE) configure_terraform && \
	$(MAKE) terraform_init > /dev/null && \
	$(MAKE) terraform_validate && \
	if [ "$(DRY_RUN)" == "true" ]; \
	then \
		$(MAKE) terraform_plan; \
	else \
		TERRAFORM_ARGS="-auto-approve" $(MAKE) terraform_apply; \
	fi

destroy_cluster:
	if [ "$(DRY_RUN)" == "true" ]; \
	then \
		$(MAKE) terraform_destroy; \
	else \
		TERRAFORM_ARGS=-auto-approve $(MAKE) terraform_destroy; \
	fi

deploy_tools_image:
	$(MAKE) build_tools_image && \
	$(MAKE) test_tools_image

.PHONY: configure_terraform lint_terraform terraform_%

configure_terraform:
	ENV_FILE=.env $(SCRIPTS_PATH)/create_terraform_configuration.sh

terraform_%:
	action=$$(echo $@ | sed 's/terraform_//'); \
	docker run --volume "$(CONTROL_PLANE_SOURCE_PATH)/aws:/infra" \
		--env-file .env \
		--env AWS_ACCESS_KEY_ID \
		--env AWS_SECRET_ACCESS_KEY \
		--env AWS_REGION \
		--env TF_VAR_provisioning_machine_ip_address $(THIS_IP_ADDRESS) \
		--workdir /infra \
		$(TERRAFORM_DOCKER_IMAGE) $$action $(TERRAFORM_ARGS)


.PHONY: \
	build_tools_image \
	test_tools_image \
	deploy_tools_image

build_tools_image:
	docker build -t $(KUBERNETES_TOOLS_IMAGE_NAME) \
		-f $(KUBERNETES_TOOLS_SOURCE_PATH)/Dockerfile \
		--quiet \
		$(KUBERNETES_TOOLS_SOURCE_PATH) > /dev/null

test_tools_image:
	docker run --volume $(KUBERNETES_TOOLS_SOURCE_PATH):/app \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		--workdir /app \
		--env DOCKER_IMAGE_UNDER_TEST=$(KUBERNETES_TOOLS_IMAGE_NAME) \
		$(BATS_DOCKER_IMAGE) /app/tests
