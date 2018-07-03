data "aws_availability_zones" "available_to_this_account" {}

locals {
  aws_tags = "${merge(var.default_tags, var.additional_tags)}"
  subnets = {
    cidr_blocks = {
      first = "${replace(var.cidr_block_for_kubernetes_clusters, "^([0-9]{1,3}\.[0.-9]{1,3}\.).*", "$1.1.0/24")}"
      second = "${replace(var.cidr_block_for_kubernetes_clusters, "^([0-9]{1,3}\.[0.-9]{1,3}\.).*", "$1.2.0/24")}"
      third = "${replace(var.cidr_block_for_kubernetes_clusters, "^([0-9]{1,3}\.[0.-9]{1,3}\.).*", "$1.3.0/24")}"
    }
    availability_zones = {
      first = "${data.aws_availability_zones.available.names[0]}"
      second = "${data.aws_availability_zones.available.names[1]}"
      third = "${data.aws_availability_zones.available.names[2]}"
    }
  }
}
