variable "number_of_zones" {
  description = "The number of zones to use for this Kubernetes deployment."
}
variable "provisioning_machine_ip_address" {
  description = "The IP address for the provisioning machine."
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
variable "base_tags" {
  description = "The basic set of tags to use for all resources created by this plan."
  type = "map"
}
variable "kubernetes_controller_asg_tags" {
  description = "Tags to apply onto all Kubernetes controllers."
  type = "list"
}
variable "kubernetes_worker_asg_tags" {
  description = "Tags to apply onto all Kubernetes workers."
  type = "list"
}

variable "kubernetes_public_port" {
  description = "The port that Kubernetes clients will connect to."
  default = 443
}
variable "kubernetes_internal_port" {
  description = "The port that Kuberenetes clients will use internally."
  default = 6443
}
variable "kubernetes_node_ami" {
  description = "The AMI to use for Kubernetes nodes."
  default = "ami-5cc39523"
}
variable "kubernetes_nodes_spot_price" {
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

variable "cidr_block_for_kubernetes_clusters" {
  description = "The CIDR block to use for Kubernetes clusters."
  default = "10.0.0.0/16"
}

variable "domain_name" {
  description = "The domain under management."
  default = "carlosnunez.me"
}
