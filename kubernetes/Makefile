#!/usr/bin/env make
MAKEOPTS += '--silent'

DOCKER_USERNAME ?= carlosonunez
BATS_DOCKER_IMAGE ?= graze/bats
CONTROL_INSTANCE_DOCKER_IMAGE_TAG ?= kubernetes_control_instance
CONTROL_INSTANCE_DOCKER_IMAGE_NAME := $(DOCKER_USERNAME)/$(CONTROL_INSTANCE_DOCKER_IMAGE_TAG)
CONTROL_INSTANCE_SOURCE_PATH := $(shell \
	echo "$$(git rev-parse --show-toplevel)/kubernetes/control_instance")

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
		$(CONTROL_INSTANCE_SOURCE_PATH)

test_control_instance_docker_image:
	docker run --volume $(CONTROL_INSTANCE_SOURCE_PATH):/app \
		--workdir /app \
		--env DOCKER_IMAGE_UNDER_TEST=$(CONTROL_INSTANCE_DOCKER_IMAGE_NAME) \
		$(BATS_DOCKER_IMAGE) /app/tests
