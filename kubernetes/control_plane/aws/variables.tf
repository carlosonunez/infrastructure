variable "number_of_zones" {
  description = "The number of zones to use for this Kubernetes deployment."
}

variable "cidr_block_for_kubernetes_clusters" {
  description = "The CIDR block to use for Kubernetes clusters."
  default = "10.0.0.0/16"
}

variable "domain_name" {
  description = "The domain under management."
  default = "carlosnunez.me"
}

variable "environment_name" {
  description = "The environment being provisioned."
}

variable "default_tags" {
  description = "Default tags to append onto every resource that supports tagging."
  type = "map"
  default = {
    Domain = "${var.domain_name}"
    Environment = "${var.environment_name}"
  }
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
