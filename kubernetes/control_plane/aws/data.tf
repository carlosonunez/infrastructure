data "aws_availability_zones" "available_to_this_account" {}

data "aws_route53_zone" "route53_zone_for_domain" {
  name = "${var.domain_name}"
}

data "template_file" "kubernetes_controller_user_data" {
  template = "${file("${path.module}/templates/user_data")}"
  vars {
    aws_region = "${ var.aws_region }"
    aws_access_key_id = "${ var.aws_access_key_id }"
    aws_secret_access_key = "${ var.aws_secret_access_key }"
    certificate_token = "${ var.certificate_token }"
    domain_name = "${ var.domain_name }"
    kubernetes_configuration_github_repository = "${var.kubernetes_configuration_github_repository}"
    kubernetes_configuration_github_branch = "${var.kubernetes_configuration_github_branch}"
    kubernetes_configuration_management_tool = "${var.kubernetes_configuration_management_code_directory}"
    kubernetes_pod_cidr = "${ var.kubernetes_pod_cidr_block }"
    ansible_vars_s3_bucket = "${var.ansible_vars_s3_bucket}"
    ansible_vars_s3_key = "${var.ansible_vars_s3_key}"
    environment_name = "${var.environment_name}"
    expected_etcd_servers = "${var.number_of_masters_per_control_plane}"
    expected_controllers = "${var.number_of_masters_per_control_plane}"
    expected_workers = "${var.number_of_workers_per_cluster}"
    route_table_id = "${aws_route_table.kubernetes_clusters.id}"
    role = "controller"
  }
}
data "template_file" "kubernetes_worker_user_data" {
  template = "${file("${path.module}/templates/user_data")}"
  vars {
    certificate_token = "${ var.certificate_token }"
    aws_region = "${ var.aws_region }"
    aws_access_key_id = "${ var.aws_access_key_id }"
    aws_secret_access_key = "${ var.aws_secret_access_key }"
    domain_name = "${ var.domain_name }"
    kubernetes_configuration_github_repository = "${var.kubernetes_configuration_github_repository}"
    kubernetes_configuration_github_branch = "${var.kubernetes_configuration_github_branch}"
    kubernetes_configuration_management_tool = "${var.kubernetes_configuration_management_code_directory}"
    kubernetes_pod_cidr = "${ var.kubernetes_pod_cidr_block }"
    ansible_vars_s3_bucket = "${var.ansible_vars_s3_bucket}"
    ansible_vars_s3_key = "${var.ansible_vars_s3_key}"
    environment_name = "${var.environment_name}"
    expected_etcd_servers = "${var.number_of_masters_per_control_plane}"
    expected_controllers = "${var.number_of_masters_per_control_plane}"
    expected_workers = "${var.number_of_workers_per_cluster}"
    route_table_id = "${aws_route_table.kubernetes_clusters.id}"
    role = "worker"
  }
}
data "template_file" "etcd_node_user_data" {
  template = "${file("${path.module}/templates/user_data")}"
  vars {
    certificate_token = "${ var.certificate_token }"
    aws_region = "${ var.aws_region }"
    aws_access_key_id = "${ var.aws_access_key_id }"
    aws_secret_access_key = "${ var.aws_secret_access_key }"
    domain_name = "${ var.domain_name }"
    kubernetes_configuration_github_repository = "${var.kubernetes_configuration_github_repository}"
    kubernetes_configuration_github_branch = "${var.kubernetes_configuration_github_branch}"
    kubernetes_configuration_management_tool = "${var.kubernetes_configuration_management_code_directory}"
    kubernetes_pod_cidr = "${ var.kubernetes_pod_cidr_block }"
    ansible_vars_s3_bucket = "${var.ansible_vars_s3_bucket}"
    ansible_vars_s3_key = "${var.ansible_vars_s3_key}"
    environment_name = "${var.environment_name}"
    expected_etcd_servers = "${var.number_of_masters_per_control_plane}"
    expected_controllers = "${var.number_of_masters_per_control_plane}"
    expected_workers = "${var.number_of_workers_per_cluster}"
    route_table_id = "${aws_route_table.kubernetes_clusters.id}"
    role = "etcd"
  }
}

locals {
  kubernetes_public_port = "${var.kubernetes_public_port}"
  kubernetes_internal_port = "${var.kubernetes_internal_port}"
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
