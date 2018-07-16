resource "aws_elb" "kubernetes_control_plane" {
  name = "kubernetes"
  subnets = [ "${aws_subnet.kubernetes_control_plane.*.id}" ]
  security_groups = [ "${aws_security_group.kubernetes_control_plane_lb.id}" ]
  listener {
    instance_port = "${local.kubernetes_internal_port}"
    instance_protocol = "TCP"
    lb_port = "${local.kubernetes_public_port}"
    lb_protocol = "TCP"
  }
  health_check {
    healthy_threshold = 3
    unhealthy_threshold = 10
    target = "HTTP:80/"
    interval = 10
    timeout = 5
  }
}

resource "aws_route53_record" "kubernetes_public_address" {
  zone_id = "${data.aws_route53_zone.route53_zone_for_domain.zone_id}"
  name = "kubernetes"
  type = "CNAME"
  ttl = "1"
  records = [ "${aws_elb.kubernetes_control_plane.dns_name}" ] 
}

output "kubernetes_control_plane_dns_address" {
  value = "${aws_route53_record.kubernetes_public_address.fqdn}"
}
