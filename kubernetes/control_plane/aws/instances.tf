resource "aws_key_pair" "kubernetes_cluster" {
  key_name = "kubernetes_cluster_${var.environment_name}"
  public_key = "${var.kubernetes_cluster_public_key}"
}

resource "aws_launch_configuration" "kubernetes_control_plane" {
  name = "kubernetes_control_plane"
  image_id = "${var.kubernetes_node_ami}"
  instance_type = "${var.kubernetes_node_instance_type}"
  key_name = "${aws_key_pair.kubernetes_cluster.key_name}"
  security_groups = [ "${aws_security_group.kubernetes_clusters.id}" ]
  associate_public_ip_address = true
  root_block_device {
    volume_type = "gp2"
    volume_size = 32
    delete_on_termination = true
  }
  spot_price = "${var.kubernetes_nodes_spot_price}"
}

resource "aws_launch_configuration" "kubernetes_workers" {
  name = "kubernetes_workers"
  image_id = "${var.kubernetes_node_ami}"
  instance_type = "${var.kubernetes_node_instance_type}"
  key_name = "${aws_key_pair.kubernetes_cluster.key_name}"
  security_groups = [ "${aws_security_group.kubernetes_clusters.id}" ]
  associate_public_ip_address = true
  root_block_device {
    volume_type = "gp2"
    volume_size = 32
    delete_on_termination = true
  }
  spot_price = "${var.kubernetes_nodes_spot_price}"
}

resource "aws_autoscaling_group" "kubernetes_control_plane" {
  name = "kubernetes_control_plane"
  max_size = "${var.number_of_masters_per_control_plane}"
  min_size = "${var.number_of_masters_per_control_plane}"
  launch_configuration = "${aws_launch_configuration.kubernetes_control_plane.name}"
  vpc_zone_identifier = [ "${aws_subnet.kubernetes_control_plane.*.id}" ]
  target_group_arns = [ "${aws_lb_target_group.kubernetes_control_plane.arn}" ]
  tags = [ "${merge(local.aws_tags, local.kubernetes_tags, var.kubernetes_control_plane_tags)}" ]
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]
}

resource "aws_autoscaling_group" "kubernetes_workers" {
  name = "kubernetes_workers"
  max_size = "${var.number_of_workers_per_cluster}"
  min_size = "${var.number_of_workers_per_cluster}"
  launch_configuration = "${aws_launch_configuration.kubernetes_control_plane.name}"
  vpc_zone_identifier = [ "${aws_subnet.kubernetes_workers.*.id}" ]
  tags = [ "${merge(local.aws_tags, local.kubernetes_tags, var.kubernetes_worker_tags)}" ]
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]
}
