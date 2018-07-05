#!/usr/bin/env bats
@test "Ensure that required packages are present" {
  for package in jq curl cfssl cfssljson
  do
    expected_exit_code=0
    run bash -c "docker run --entrypoint bash  \
    "$DOCKER_IMAGE_UNDER_TEST" \
    -c 'which $package'"
    >&2 echo "Test failed. Output: $output. Expected: /usr/local/bin/$package"
    [ "$status" -eq "$expected_exit_code" ]
    [ "$output" == "/usr/bin/$package" ]
  done
}
