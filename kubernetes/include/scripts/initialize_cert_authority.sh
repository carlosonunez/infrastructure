#!/usr/bin/env bash
set -e
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]
then
  >&2 echo "WARNING: No .env file was provided. Using local environment instead."
else
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi
DOCKER_IMAGE="${DOCKER_IMAGE?Please provide the image name containing our tools.}"
CA_KEY_S3_BUCKET_NAME="${CA_KEY_S3_BUCKET_NAME?Please provide the bucket containing our cert auth keys within S3.}"
CA_KEY_S3_KEY_PATH="${CA_KEY_S3_KEY_PATH?Please provide the path to our cert auth keys within S3.}"
CA_CSR_CITY="${CA_CSR_CITY?Please provide a city to use for our cert authority.}"
CA_CSR_STATE="${CA_CSR_STATE?Please provide a state to use for our cert authority.}"
CA_CSR_COUNTRY_INITIALS="${CA_CSR_COUNTRY_INITIALS?Please provide a country (initials only) to use for our cert authority.}"
CA_CSR_ORGANIZATION="${CA_CSR_ORGANIZATION?Please provide a organization to use for our cert authority.}"
CA_CSR_COMMON_NAME="${CA_CSR_COMMON_NAME?Please provide a common name to use for our cert authority.}"
CA_CONFIG_JSON=$(cat <<CERT_AUTHORITY_CONFIG
{
  \"signing\": {
    \"default\": {
      \"expiry\": \"8760h\"
    },
    \"profiles\": {
      \"kubernetes\": {
        \"usages\": [ \"signing\", \"key encipherment\", \"server auth\", \"client auth\" ],
        \"expiry\": \"8760h\"
      }
    }
  }
}
CERT_AUTHORITY_CONFIG
)
CA_CSR_CONFIG_JSON=$(cat <<CSR_CONFIG
{
  \"CN\": \"$CA_CSR_COMMON_NAME\",
  \"key\": {
    \"algo\": \"rsa\",
    \"size\": 2048
  },
  \"names\": [
    {
      \"C\": \"$CA_CSR_COUNTRY_INITIALS\",
      \"L\": \"$CA_CSR_CITY\",
      \"O\": \"$CA_CSR_ORGANIZATION\",
      \"OU\": \"CA\",
      \"ST\": \"$CA_CSR_STATE\"
    }
  ]
}
CSR_CONFIG
)

check_if_cert_authority_files_are_present() {
  s3_path="${CA_KEY_S3_BUCKET_NAME}/${CA_KEY_S3_KEY_PATH}"
  if ! aws s3 ls "s3://${s3_path}" &>/dev/null
  then
    return 1
  fi
  for file in ca.pem ca-key.pem
  do
    if ! aws s3 ls "s3://${s3_path}/${file}" &>/dev/null
    then
      return 1
    fi
  done
  return 0
}

create_cert_authority_s3_bucket_if_needed() {
  if ! aws s3 ls "s3://${CA_KEY_S3_BUCKET_NAME}"
  then
    >&2 echo "INFO: Creating S3 bucket: ${CA_KEY_S3_BUCKET_NAME}"
    aws s3 mb "s3://${CA_KEY_S3_BUCKET_NAME}"
  fi
}

generate_and_upload_ca_certificates() {
	command_to_run=$(cat <<BASH_SCRIPT
echo "$CA_CONFIG_JSON" > ca-config.json && \
echo "$CA_CSR_CONFIG_JSON" | cfssl gencert -initca - | cfssljson -bare ca && \
mv *.pem /keys && \
chown -R "$(id -u)" /keys/ca*.pem
BASH_SCRIPT
)
	docker run --interactive \
		--entrypoint bash \
		--volume /tmp:/keys \
    --user root \
		"$DOCKER_IMAGE" \
		-c "$command_to_run"
  if [ -f /tmp/ca.pem ] && [ -f /tmp/ca-key.pem ]
  then
    for file in ca.pem ca-key.pem
    do
      aws s3 cp "/tmp/$file" "s3://${CA_KEY_S3_BUCKET_NAME}/${CA_KEY_S3_KEY_PATH}/$file"
    done
  else
    >&2 echo "ERROR: cfssl succeeded but failed to write files."
    return 1
  fi
}

if check_if_cert_authority_files_are_present
then
  >&2 echo "INFO: Certificate authority files have already been provisioned. Nothing to do."
  exit 0
fi
if ! {
  create_cert_authority_s3_bucket_if_needed &&
  generate_and_upload_ca_certificates;
}
then
  >&2 echo "ERROR: Unable to create or upload CA certificates. Aborting."
  exit 1
fi
exit 0
