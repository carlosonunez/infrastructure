resource "aws_eip" "kubernetes_control_plane_lb" {
  vpc = true
}

output "kubernetes_control_plane_lb_ip_address" {
  value = "${aws_eip.kubernetes_control_plane_lb.public_ip}"
}
