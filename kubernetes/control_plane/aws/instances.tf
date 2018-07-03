resource "aws_spot_fleet_request" "kubernetes_control_plane" {
  depends_on = [
    "${aws_iam_service_linked_role.aws_spot}",
    "${aws_iam_service_linked_role.aws_spot_fleet}",
    "${aws_iam_role_policy_attachment.kubernetes_control_plane_spot_fleet}"
  ]
  iam_fleet_role = "${aws_iam_role.kubernetes_control_plane_spot_fleet.arn}"
  spot_price     = "${var.kubernetes_nodes_spot_price}"
  wait_for_fulfillment = true
  target_capacity = "${var.number_of_zones}"
  allocation_strategy = "lowestPrice"
  excess_capacity_termination_strategy = "default"
  terminate_instances_with_expiration = true
  timeouts {
    create = 2
    delete = 2
  }
  launch_specification {
    ami_id = "${local.ami_to_use_for_kubernetes_nodes}"
    availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
    ebs_optimized = false
    instance_type = "${var.kubernetes_node_instance_type}"
    key_name = "${aws_key_pair.kubernetes_nodes.name}"
    vpc_security_group_ids = [ "${aws_security_group.kubernetes_cluster.id}" ]
    subnet_id = "${aws_subnet.kubernetes_cluster.*.id[count.index]}"
    associate_public_ip_address = true
    tags = "${merge(local.aws_tags, var.kubernetes_control_plane_tags)}"
  }
}

resource "aws_instance" "kubernetes_control_plane" {
}
