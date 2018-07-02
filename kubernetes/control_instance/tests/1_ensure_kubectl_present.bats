#!/usr/bin/env bats
load helpers/pre_and_post

@test "Ensure that kubectl is present" {
  expected_exit_code=0
  run "docker run -it --entrypoint bash $CONTROL_INSTANCE_DOCKER_IMAGE_NAME \
    -c 'which kubectl > /dev/null'
  [ "$status" -eq "$expected_exit_code" ]
}
