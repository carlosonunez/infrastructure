data "aws_availability_zones" "available_to_this_account" {}

locals {
  default_tags = {
    Domain = "${var.domain_name}"
    Environment = "${var.environment_name}"
  }
  aws_tags = "${merge(local.default_tags, var.additional_tags)}"
  subnet_cidr_blocks = [
    "${replace(var.cidr_block_for_kubernetes_clusters, "/^([0-9]{1,3}.[0-9]{1,3}).*/", "$1.1.0/24")}",
    "${replace(var.cidr_block_for_kubernetes_clusters, "/^([0-9]{1,3}.[0-9]{1,3}).*/", "$1.2.0/24")}",
    "${replace(var.cidr_block_for_kubernetes_clusters, "/^([0-9]{1,3}.[0-9]{1,3}).*/", "$1.3.0/24")}"
  ]
}
