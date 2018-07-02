#!/usr/bin/env bash
CONTROL_INSTANCE_DOCKER_IMAGE_NAME_PREFIX="local/test_control_instance"

_build_test_docker_image() {
  git_repository_root=$(git rev-parse --show-toplevel)
  control_instance_source_path="${git_repository_root}/kubernetes/control_instance"
  export CONTROL_INSTANCE_DOCKER_IMAGE_NAME="${CONTROL_INSTANCE_DOCKER_IMAGE_NAME_PREFIX}_$RANDOM"
  docker build --file="${control_instance_source_path}/Dockerfile" \
    --tag local/test_control_instance \
   "${control_instance_source_path}" 
}

_remove_test_docker_images() {
  docker images | \
    grep "local/test_control_instance" | \
    awk '{print $3}' | \
    xargs docker rmi
  unset CONTROL_INSTANCE_DOCKER_IMAGE_NAME
}

setup() {
  _build_test_docker_image
}

teardown() {
  _remove_test_docker_images
}
