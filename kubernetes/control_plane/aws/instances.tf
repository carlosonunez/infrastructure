resource "aws_key_pair" "kubernetes_cluster" {
  key_name = "kubernetes_cluster_${var.environment_name}"
  public_key = "${var.kubernetes_cluster_public_key}"
}

resource "aws_spot_instance_request" "kubernetes_control_plane" {
  count = "${var.number_of_masters_per_control_plane}"
  spot_price = "${var.kubernetes_nodes_spot_price}"
  instance_type = "${var.kubernetes_node_instance_type}"
  ami = "${var.kubernetes_node_ami}"
  availability_zone = "${element(local.availability_zones_to_use, count.index)}"
  ebs_optimized = false
  key_name = "${aws_key_pair.kubernetes_cluster.key_name}"
  vpc_security_group_ids = [ "${aws_security_group.kubernetes_clusters.id}" ]
  subnet_id = "${element(aws_subnet.kubernetes_control_plane.*.id, count.index)}"
  associate_public_ip_address = true
  tags = "${merge(local.aws_tags, local.kubernetes_tags, var.kubernetes_control_plane_tags)}"
  wait_for_fulfillment = "true"
  root_block_device {
    volume_type = "gp2"
    volume_size = 32
    delete_on_termination = true
  }
}

output "kubernetes_control_plane_ip_addresses" {
  value = "${aws_spot_instance_request.kubernetes_control_plane.*.public_ip}"
}

resource "aws_spot_instance_request" "kubernetes_workers" {
  count = "${var.number_of_zones * var.number_of_workers_per_cluster}"
  spot_price = "${var.kubernetes_nodes_spot_price}"
  instance_type = "${var.kubernetes_node_instance_type}"
  ami = "${var.kubernetes_node_ami}"
  availability_zone = "${element(local.availability_zones_to_use, count.index)}"
  ebs_optimized = false
  key_name = "${aws_key_pair.kubernetes_cluster.key_name}"
  vpc_security_group_ids = [ "${aws_security_group.kubernetes_clusters.id}" ]
  subnet_id = "${element(aws_subnet.kubernetes_workers.*.id, count.index)}"
  associate_public_ip_address = true
  tags = "${merge(local.aws_tags, local.kubernetes_tags, var.kubernetes_worker_tags)}"
  wait_for_fulfillment = "true"
  root_block_device {
    volume_type = "gp2"
    volume_size = 32
    delete_on_termination = true
  }
}

output "kubernetes_workers_ip_addresses" {
  value = "${aws_spot_instance_request.kubernetes_workers.*.public_ip}"
}

