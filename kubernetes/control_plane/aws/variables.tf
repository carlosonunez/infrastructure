variable "number_of_zones" {
  description = "The number of zones to use for this Kubernetes deployment."
}
variable "provisioning_machine_ip_address" {
  description = "The IP address for the provisioning machine."
}
variable "environment_name" {
  description = "The environment being provisioned."
}
variable "kubernetes_node_ami_id" {
  description = "The AMI id to use for *all* Kubernetes nodes."
}
variable "kubernetes_node_instance_type" {
  description = <<EOF
The instance type to use for Kubernetes nodes.
Because Kubernetes is memory-intensive, we recommend using a memory-optimized
instance, such as an m* series.
EOF
}

variable "cidr_block_for_kubernetes_clusters" {
  description = "The CIDR block to use for Kubernetes clusters."
  default = "10.0.0.0/16"
}

variable "domain_name" {
  description = "The domain under management."
  default = "carlosnunez.me"
}

variable "additional_tags" {
  description = "Additional tags to append onto resources that support tagging."
  type = "map"
  default = {}
}

variable "kubernetes_cluster_vpc_tags" {
  description = "Tags to apply onto the VPC created for k8s clusters."
  default = {}
}

variable "kubernetes_cluster_subnet_tags" {
  description = "Tags to apply onto the subnets created for k8s clusters."
  default = {}
}

variable "kubernetes_control_plane_security_group_tags" {
  description = "Custom tags to use for the security group associated with the control plane"
  default = {}
}
