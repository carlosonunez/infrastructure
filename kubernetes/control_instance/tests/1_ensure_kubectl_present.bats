#!/usr/bin/env bats
@test "Ensure that a Docker image was provided" {
  [ "$DOCKER_IMAGE_UNDER_TEST" != "" ]
}

@test "Ensure that kubectl is present and in the right place" {
  expected_exit_code=0
  run bash -c "docker run --entrypoint bash  \
    "$DOCKER_IMAGE_UNDER_TEST" \
    -c 'kubectl version --client'"
  >&2 echo "Test failed. Output: $output"
  [ "$status" -eq "$expected_exit_code" ]
  [ "$output" != "" ]
}
