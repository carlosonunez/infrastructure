resource "aws_security_group" "kubernetes_clusters" {
  name = "kubernetes_control_plane"
  vpc_id = "${aws_vpc.kubernetes_clusters.id}"
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    self = true
  }
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [ "${var.provisioning_machine_ip_address}/32" ]
  }
  ingress {
    from_port = 6443
    to_port = 6443
    protocol = "tcp"
    cidr_blocks = [ "${var.provisioning_machine_ip_address}/32" ]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  tags = "${merge(local.aws_tags, var.kubernetes_control_plane_security_group_tags)}"
}
