#!/usr/bin/env make
MAKEFLAGS += '--silent'

ifeq ($(AWS_ACCESS_KEY_ID),)
$(error Please provide an access key to an AWS account)
endif
ifeq ($(AWS_SECRET_ACCESS_KEY),)
$(error Please provide a secret key to an AWS account)
endif

AWS_REGION ?= us-east-1
DOCKER_USERNAME ?= carlosonunez
BATS_DOCKER_IMAGE ?= graze/bats
KUBERNETES_TOOLS_DOCKER_IMAGE_TAG ?= k8s_tools
KUBERNETES_TOOLS_IMAGE_NAME := $(DOCKER_USERNAME)/$(KUBERNETES_TOOLS_DOCKER_IMAGE_TAG)
KUBERNETES_TOOLS_SOURCE_PATH := $(shell \
	echo "$$(git rev-parse --show-toplevel)/kubernetes/tools")
CONTROL_PLANE_SOURCE_PATH := $(shell \
	echo "$$(git rev-parse --show-toplevel)/kubernetes/control_plane")
SCRIPTS_PATH := $(shell \
	echo "$$(git rev-parse --show-toplevel)/kubernetes/include/scripts")
NUMBER_OF_AVAILABILITY_ZONES ?= 3
ENVIRONMENT_NAME ?= develop

.PHONY: deploy_cluster deploy_tools_image

deploy_cluster:
	$(MAKE) configure_terraform

deploy_tools_image:
	$(MAKE) create_tools_image && \
	$(MAKE) test_tools_image

.PHONY: configure_terraform

configure_terraform:
	$(SCRIPTS_PATH)/create_terraform_configuration.sh

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
