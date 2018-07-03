data "aws_availability_zones" "available_to_this_account" {}

# See https://github.com/hashicorp/terraform/issues/16380 for why
# we have to do it this way.
data "aws_ami" "kubernetes_nodes" {
  count = "${var.search_for_packer_generated_amis}"
  most_recent = true
  owners = self
  name_regex = "^kubernetes_node_ami-.*"
}

locals {
  default_tags = {
    Domain = "${var.domain_name}"
    Environment = "${var.environment_name}"
  }
  default_kubernetes_nodes_ami = "ami-5cc39523"
  ami_to_use_for_kubernetes_nodes = "${coalesce(data.aws_ami.kubernetes_nodes,
    local.default_kubernetes_nodes_ami)}"
  aws_tags = "${merge(local.default_tags, var.additional_tags)}"
  max_zones = 3
  subnet_cidr_blocks = [
    "${replace(var.cidr_block_for_kubernetes_clusters, "/^([0-9]{1,3}.[0-9]{1,3}).*/", "$1.1.0/24")}",
    "${replace(var.cidr_block_for_kubernetes_clusters, "/^([0-9]{1,3}.[0-9]{1,3}).*/", "$1.2.0/24")}",
    "${replace(var.cidr_block_for_kubernetes_clusters, "/^([0-9]{1,3}.[0-9]{1,3}).*/", "$1.3.0/24")}"
  ]
}
