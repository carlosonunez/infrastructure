#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/kubernetes/include/scripts/helpers/ssh.bash"
source "$(git rev-parse --show-toplevel)/kubernetes/include/scripts/helpers/remote_systemd.bash"
source "$(git rev-parse --show-toplevel)/kubernetes/include/scripts/helpers/cluster_operations.bash"
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]
then
  >&2 echo "WARNING: No .env file was provided. Using local environment instead."
else
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi
KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES=${KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES?Please provide a list of all control plane addresses in this cluster.}
SSH_USER_NAME="${SSH_USER_NAME?Please provide the user to SSH as.}"
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH?Please provide the private key to use for the SSH connection.}"
FIRST_KUBERNETES_CONTROLLER="$(echo $KUBERNETES_CONTROLLERS_PUBLIC_IP_ADDRESSES | \
    tr ',' '\n' | \
    head -1
)"

enable_rbac() {
  >&2 echo "INFO: Creating cluster-wide RBAC role."
  deploy_manifest_to "$FIRST_KUBERNETES_CONTROLLER" "$(cat <<CLUSTER_ROLE
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
CLUSTER_ROLE
  )"
  command_to_confirm_that_role_was_added="kubectl get \
    --kubeconfig admin.kubeconfig \
    clusterroles system:kube-apiserver-to-kubelet >/dev/null" 
  if ! _run_command_on_single_kubernetes_node "$FIRST_KUBERNETES_CONTROLLER" \
    "$command_to_confirm_that_role_was_added"
  then
    >&2 echo "ERROR: The cluster role above was not added."
    return 1
  fi
}

bind_kubernetes_user_to_cluster_role() {
  >&2 echo "INFO: Binding the 'kubernetes' user to the cluster-wide RBAC role."
  deploy_manifest_to "$FIRST_KUBERNETES_CONTROLLER" "$(cat <<MANIFEST
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
MANIFEST
)"
  command_to_confirm_that_role_was_added="kubectl get \
    --kubeconfig admin.kubeconfig \
    clusterrolebindings/system:kube-apiserver >/dev/null"
  if ! _run_command_on_single_kubernetes_node "$FIRST_KUBERNETES_CONTROLLER" \
    "$command_to_confirm_that_role_was_added"
  then
    >&2 echo "ERROR: The cluster role binding above was not added."
    return 1
  fi
}

enable_rbac && bind_kubernetes_user_to_cluster_role
