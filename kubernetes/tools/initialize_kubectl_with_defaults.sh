#!/usr/bin/env bash
KUBERNETES_CLUSTER_ADDRESS="${KUBERNETES_CLUSTER_ADDRESS:-127.0.0.1}"
KUBERNETES_CLUSTER_NAME="${KUBERNETES_CLUSTER_NAME:-kubernetes}"
KUBERNETES_CERT_PATH="${KUBERNETES_CERT_PATH:-/certs}"
KUBERNETES_USER_NAME="${KUBERNETES_USER_NAME:-admin}"
KUBERNTES_CLUSTER_CONTEXT="${KUBERNTES_CLUSTER_CONTEXT:-kubernetes}"
USER_CERT="${USER_CERT:-$KUBERNETES_CERT_PATH/admin.pem}"
USER_CERT_PRIVATE_KEY="${USER_CERT_PRIVATE_KEY:-$KUBERNETES_CERT_PATH/admin-key.pem}"
CA_CERT="${CA_CERT:-$KUBERNETES_CERT_PATH/ca.pem}"
usage() {
  cat <<USAGE
[ENVIRONMENT_VARIABLES] $(basename $0)
Initializes kubectl with defaults from Kubernetes The Hard Way.

Environment Variables:

  KUBERNETES_CLUSTER_ADDRESS   The cluster address to connect to.
  KUBERNETES_CLUSTER_NAME      The name of the cluster to connect to.
  KUBERNETES_CERT_PATH         The path containing the certs required to connect
                                to the cluster.
  KUBERNETES_USER_NAME         The user to connect as.
  KUBERNTES_CLUSTER_CONTEXT    The context to use for this session.
  USER_CERT                    The certificate to use for the user provided.
  USER_CERT_PRIVATE_KEY        The private key for USER_CERT.
  CA_CERT                      The cert of the issuing certificate authority
                                for USER_CERT and USER_CERT_PRIVATE_KEY.

Defaults:

  KUBERNETES_CLUSTER_ADDRESS:     ${KUBERNETES_CLUSTER_ADDRESS}
  KUBERNETES_CLUSTER_NAME:        ${KUBERNETES_CLUSTER_NAME}
  KUBERNETES_CERT_PATH:           ${KUBERNETES_CERT_PATH}
  KUBERNETES_USER_NAME:           ${KUBERNETES_USER_NAME}
  KUBERNTES_CLUSTER_CONTEXT:      ${KUBERNTES_CLUSTER_CONTEXT}
  USER_CERT:                      ${USER_CERT}
  USER_CERT_PRIVATE_KEY:          ${USER_CERT}
  CA_CERT:                        ${CA_CERT}
USAGE
}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]
then
  usage
  exit 0
fi

ensure_kubectl_is_installed_or_die() {
  if ! which kubectl &>/dev/null
  then
    >&2 echo "ERROR: kubectl is not installed."
    exit 1
  fi
}

ensure_certs_are_provided_or_die() {
  for cert in "$USER_CERT" "$USER_CERT_PRIVATE_KEY" "$CA_CERT"
  do
    if [ ! -f "${cert}" ]
    then
      >&2 echo "ERROR: Missing certificate: ${cert}"
      exit 1
    fi
  done
}

set_kubernetes_cluster() {
  kubectl config set-cluster "${KUBERNETES_CLUSTER_NAME}" \
    --certificate-authority=$CA_CERT \
    --embed-certs=true \
    --server=https://${KUBERNETES_CLUSTER_ADDRESS}:6443
}

set_credentials() {
  kubectl config set-credentials "${KUBERNETES_USER_NAME}" \
    --client-certificate="${USER_CERT}" \
    --client-key="${USER_CERT_PRIVATE_KEY}"
}

set_cluster_context() {
  kubectl config set-context "$KUBERNTES_CLUSTER_CONTEXT" \
    --cluster="$KUBERNETES_CLUSTER_NAME" \
    --user="$KUBERNETES_USER_NAME"
}

enable_context() {
  kubectl config use-context "$KUBERNTES_CLUSTER_CONTEXT"
}

ensure_kubectl_is_installed_or_die &&
  ensure_certs_are_provided_or_die &&
  set_kubernetes_cluster &&
  set_credentials &&
  set_cluster_context &&
  enable_context
