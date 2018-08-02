variable "aws_access_key_id" {}
variable "aws_secret_access_key" {}
variable "aws_region" {}
variable "number_of_zones" {
  description = "The number of zones to use for this Kubernetes deployment."
}
variable "provisioning_machine_ip_address" {
  description = "The IP address for the provisioning machine."
}
variable "certificate_token" {
  description = "A short, unique identifier to use when searching for certificates within S3."
}
variable "environment_name" {
  description = "The environment being provisioned."
}
variable "kubernetes_cluster_public_key" {
  description = "The public key to use for the SSH key provisioned for Kubernetes nodes."
}
variable "number_of_masters_per_control_plane" {
  description = "The number of masters to deploy per control plane. This cannot exceed number_of_zones."
}
variable "number_of_workers_per_cluster" {
  description = "The number of workers to provision per cluster."
}
variable "kubernetes_version" {
  description = "The version of Kubernetes this cluster is running. Used for tagging purposes only."
}
variable "kubernetes_public_port" {
  description = "The port to access Kubernetes on publically."
}
variable "ansible_vars_s3_bucket" {
  description = "The bucket containing Ansible variables."
}
variable "ansible_vars_s3_key" {
  description = "The key within ansible_vars_s3_bucket."
}
variable "kubernetes_pod_cidr_block" {
  description = "The CIDR block to assign (internally) to the Kubernetes cluster."
}
variable "kubernetes_internal_port" {
  description = "The port to access Kubernetes on internally."
  default = 6443
}
variable "kubernetes_configuration_github_branch" {
  description = "The branch to use for kubernetes_configuration_github_repository"
}
variable "base_tags" {
  description = "The basic set of tags to use for all resources created by this plan."
  type = "map"
}
variable "etcd_tags" {
  description = "Tags to apply onto all etcd nodes."
  type = "map"
}
variable "kubernetes_controller_tags" {
  description = "Tags to apply onto all Kubernetes controllers."
  type = "map"
}
variable "kubernetes_worker_tags" {
  description = "Tags to apply onto all Kubernetes workers."
  type = "map"
}
variable "kubernetes_node_ami" {
  description = "The AMI to use for Kubernetes nodes."
  default = "ami-5cc39523"
}
variable "etcd_node_ami" {
  description = "The AMI to use for Kubernetes nodes."
  default = "ami-5cc39523"
}
variable "kubernetes_nodes_spot_price" {
  description = "The spot price to set for Kubernetes nodes."
  default = "0.0145"
}
variable "etcd_nodes_spot_price" {
  description = "The spot price to set for Kubernetes nodes."
  default = "0.0145"
}

variable "search_for_packer_generated_amis" {
  description = "Set this to use Packer-generated AMIs instead of the default Ubuntu AMI."
  default = false
}

variable "kubernetes_node_instance_type" {
  description = <<EOF
The instance type to use for Kubernetes nodes.
Because Kubernetes is memory-intensive, we recommend using a memory-optimized
instance, such as an m* series.
EOF
  default = "t2.medium"
}

variable "etcd_node_instance_type" {
  description = <<EOF
The instance type to use for etcd nodes.
Because etcd is memory-intensive, we recommend using a memory-optimized
instance, such as an m* series.
EOF
  default = "t2.medium"
}

variable "cidr_block_for_kubernetes_clusters" {
  description = "The CIDR block to use for Kubernetes clusters."
  default = "10.0.0.0/16"
}

variable "domain_name" {
  description = "The domain under management."
  default = "carlosnunez.me"
}

variable "kubernetes_configuration_github_repository" {
  description = "The Git repository containining configuration code for our Kubernetes cluster."
  default = "https://github.com/carlosonunez/infrastructure"
}

variable "kubernetes_configuration_management_code_directory" {
  description = "The path containing our configuration management code within the kubernetes_configuration_github_repository."
  default = "ansible"
}

variable "seconds_to_wait_for_worker_fulfillment" {
  description = "Number of seconds to wait for the Kubernetes workers to start up. This is required to successfully provision aws_routes for the Pods that they will be hosting."
  default = 30
}
