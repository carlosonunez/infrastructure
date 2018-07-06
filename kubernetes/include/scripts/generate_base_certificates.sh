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
{\
  \"signing\": {\
    \"default\": {\
      \"expiry\": \"8760h\"\
    },\
    \"profiles\": {\
      \"kubernetes\": {\
        \"usages\": [ \"signing\", \"key encipherment\", \"server auth\", \"client auth\" ],\
        \"expiry\": \"8760h\"\
      }\
    }\
  }\
}
CERT_AUTHORITY_CONFIG
)
CA_CSR_TEMPLATE=$(cat <<CSR_CONFIG
{\
  \"CN\": \"<common_name>\",\
  \"key\": {\
    \"algo\": \"rsa\",\
    \"size\": 2048\
  },\
  \"names\": [\
    {\
      \"C\": \"$CA_CSR_COUNTRY_INITIALS\",\
      \"L\": \"$CA_CSR_CITY\",\
      \"OU\": \"CA\",\
      \"ST\": \"$CA_CSR_STATE\",\
      \"O\": \"<organization_name>\"\
    }\
  ]\
}
CSR_CONFIG
)
common_name_org_name_kvps=$(cat <<KVPS
Kubernetes#Kubernetes#ca,\
admin#system:masters#admin,\
system:kube-controller-manager#system:kube-controller-manager#kube-controller-manager,\
system:kube-proxy#system:node-proxier#kube-proxy,\
system:kube-scheduler#system:kube-scheduler#kube-scheduler,\
service-accounts#Kubernetes#service-account
KVPS
)

generate_and_upload_ca_certificates() {
	command_to_run=$(cat <<BASH_SCRIPT
>&2 echo "INFO: Creating certificate authority certificate" && \
echo "$CA_CONFIG_JSON" > ca-config.json && \
cp ca-config.json /keys && \
for kvp in \$(echo "$common_name_org_name_kvps" | tr ',' "\n"); \
do \
	>&2 echo "INFO: Creating certificate for kvp: \$kvp"; \
	common_name=\$(echo "\$kvp" | cut -f1 -d '#'); \
	org_name=\$(echo "\$kvp" | cut -f2 -d '#'); \
	file_name=\$(echo "\$kvp" | cut -f3 -d '#'); \
	new_csr_json=\$(echo "$CA_CSR_TEMPLATE" | \
		sed "s/<common_name>/\$common_name/" | \
		sed "s/<organization_name>/\$org_name/"); \
	if [ "\$file_name" == "ca" ]; \
	then \
		echo "\$new_csr_json" | cfssl gencert -initca - | cfssljson -bare "\$file_name"; \
	else \
		echo "\$new_csr_json" | \
			cfssl gencert \
				-ca=ca.pem \
				-ca-key=ca-key.pem \
				-config=ca-config.json \
				-profile=kubernetes - | cfssljson -bare "\$file_name"; \
	fi; \
done && \
mv *.pem /keys && \
chown -R "$(id -u)" /keys/*.pem
BASH_SCRIPT
)
	if ! docker run --interactive \
		--entrypoint bash \
		--volume /tmp:/keys \
    --user root \
		"$DOCKER_IMAGE" \
		-c "$command_to_run"
	then
		>&2 echo "ERROR: Failed to create some certificates; see log for more info."
		return 1
	fi
}

if ! generate_and_upload_ca_certificates
then
  >&2 echo "ERROR: Unable to create or upload CA certificates. Aborting."
  exit 1
fi
exit 0
