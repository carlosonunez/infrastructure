resource "aws_security_group" "kubernetes_control_plane_lb" {
  name = "kubernetes_lb"
  description = "Allows inbound access to this Kubernetes cluster"
  tags = "${var.base_tags}"
  vpc_id = "${aws_vpc.kubernetes_clusters.id}"
  ingress {
    from_port = "${local.kubernetes_public_port}"
    to_port = "${local.kubernetes_public_port}"
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port = 0
    to_port = 0 
    protocol = -1
    cidr_blocks = [ "0.0.0.0/0" ]
  }
}

resource "aws_security_group" "kubernetes_clusters" {
  name = "kubernetes_control_plane"
  vpc_id = "${aws_vpc.kubernetes_clusters.id}"
  tags = "${var.base_tags}"
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
    from_port = "${var.kubernetes_internal_port}"
    to_port = "${var.kubernetes_internal_port}"
    protocol = "tcp"
    security_groups = [ "${aws_security_group.kubernetes_control_plane_lb.id}" ]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
}
