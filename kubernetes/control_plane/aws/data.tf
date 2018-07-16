data "aws_availability_zones" "available_to_this_account" {}

data "aws_route53_zone" "route53_zone_for_domain" {
  name = "${var.domain_name}"
}

locals {
  kubernetes_public_port = 6443
  kubernetes_internal_port = 6443
  availability_zones_to_use = "${slice(data.aws_availability_zones.available_to_this_account.names,
    0,
    var.number_of_zones
  )}"
  number_of_availabilty_zones_being_used = "${length(local.availability_zones_to_use)}"
  number_of_kubernetes_workers_to_deploy_per_cluster = "${var.number_of_workers_per_cluster * local.number_of_availabilty_zones_being_used}"
  subnet_cidr_blocks = [
    "${replace(var.cidr_block_for_kubernetes_clusters, "/^([0-9]{1,3}.[0-9]{1,3}).*/", "$1.1.0/24")}",
    "${replace(var.cidr_block_for_kubernetes_clusters, "/^([0-9]{1,3}.[0-9]{1,3}).*/", "$1.2.0/24")}",
    "${replace(var.cidr_block_for_kubernetes_clusters, "/^([0-9]{1,3}.[0-9]{1,3}).*/", "$1.3.0/24")}"
  ]
  worker_subnet_cidr_blocks = [
    "${replace(var.cidr_block_for_kubernetes_clusters, "/^([0-9]{1,3}.[0-9]{1,3}).*/", "$1.4.0/24")}",
    "${replace(var.cidr_block_for_kubernetes_clusters, "/^([0-9]{1,3}.[0-9]{1,3}).*/", "$1.5.0/24")}",
    "${replace(var.cidr_block_for_kubernetes_clusters, "/^([0-9]{1,3}.[0-9]{1,3}).*/", "$1.6.0/24")}"
  ]
}
