#!/usr/bin/env bash
AWSCLI_DOCKER_IMAGE="${AWSCLI_DOCKER_IMAGE:-anigeo/awscli}"
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]
then
  >&2 echo "WARNING: No .env file was provided. Using local environment instead."
else
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

docker run --volume "$HOME/.aws:/root/.aws" \
  --env-file "$ENV_FILE" \
  "$AWSCLI_DOCKER_IMAGE" \
  ec2 describe-instances \
    --filter "Name=tag:kubernetes_role,Value=controller" \
    --filter "Name=tag:kubernetes_role,Values=worker" \
    --query "Reservations[*].Instances[*].PublicIpAddress"
