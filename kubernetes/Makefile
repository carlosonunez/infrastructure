#!/usr/bin/env make
MAKEFLAGS += '--silent'

ifeq ($(AWS_ACCESS_KEY_ID),)
$(error "Please provide an access key to an AWS account.")
endif
ifeq ($(AWS_SECRET_ACCESS_KEY),)
$(error "Please provide a secret key to an AWS account.")
endif

AWS_REGION ?= us-east-1
DOCKER_USERNAME ?= carlosonunez
BATS_DOCKER_IMAGE ?= graze/bats
CONTROL_INSTANCE_DOCKER_IMAGE_TAG ?= kubernetes_control_instance
CONTROL_INSTANCE_DOCKER_IMAGE_NAME := $(DOCKER_USERNAME)/$(CONTROL_INSTANCE_DOCKER_IMAGE_TAG)
CONTROL_INSTANCE_SOURCE_PATH := $(shell \
	echo "$$(git rev-parse --show-toplevel)/kubernetes/control_instance")
NUMBER_OF_AVAILABILITY_ZONES ?= 3
ENVIRONMENT_NAME ?= develop

.PHONY: \
	validate_helper_scripts \
	test_helper_scripts \
	validate_terraform \
	test_terraform

.PHONY: \
	create_terraform_configuration \
	terraform_init \
	terraform_get \
	terraform_lint \
	terraform_plan \
	terraform_destroy

.PHONY: \
	generate_control_instance_docker_image \
	build_control_instance_docker_image \
	test_control_instance_docker_image \
	deploy_control_instance_docker_image

generate_control_instance_docker_image: build_control_instance_docker_image \
	test_control_instance_docker_image

build_control_instance_docker_image:
	docker build -t $(CONTROL_INSTANCE_DOCKER_IMAGE_NAME) \
		-f $(CONTROL_INSTANCE_SOURCE_PATH)/Dockerfile \
		--quiet \
		$(CONTROL_INSTANCE_SOURCE_PATH) > /dev/null

test_control_instance_docker_image:
	docker run --volume $(CONTROL_INSTANCE_SOURCE_PATH):/app \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		--workdir /app \
		--env DOCKER_IMAGE_UNDER_TEST=$(CONTROL_INSTANCE_DOCKER_IMAGE_NAME) \
		$(BATS_DOCKER_IMAGE) /app/tests
