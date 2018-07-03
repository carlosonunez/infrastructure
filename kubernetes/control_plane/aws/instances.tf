resource "aws_instance" "kubernetes_control_plane" {
  count = "${var.number_of_zones}"
  ami_id = "${var.kubernetes_node_ami_id}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  ebs_optimized = false
  instance_type = "${var.kubernetes_node_instance_type}"
  key_name = "${aws_key_pair.kubernetes_nodes.name}"
  vpc_security_group_ids = [ "${aws_security_group.kubernetes_cluster.id}" ]
  subnet_id = "${aws_subnet.kubernetes_cluster.*.id[count.index]}"
  associate_public_ip_address = true
  tags = "${merge(local.aws_tags, var.kubernetes_control_plane_tags)}"
}
