resource "aws_lb_target_group" "kubernetes_control_plane" {
  name = "kubernetes-control-plane"
  port = "${local.kubernetes_internal_port}"
  protocol = "HTTP"
  vpc_id = "${aws_vpc.kubernetes_clusters.id}"
  target_type = "instance"
  tags = "${merge(local.aws_tags, local.kubernetes_tags, var.kubernetes_control_plane_tags)}"
  health_check {
    interval = 10
    path = "/healthz"
    port = "80"
    protocol = "HTTP"
    timeout = 5
    healthy_threshold = 3
    unhealthy_threshold = 5
    matcher = "200"
  }
}

resource "aws_lb_target_group_attachment" "kubernetes_control_plane" {
  count = "${var.number_of_masters_per_control_plane}"
  target_group_arn = "${aws_lb_target_group.kubernetes_control_plane.arn}"
  target_id = "${element(aws_spot_instance_request.kubernetes_control_plane.*.spot_instance_id, count.index)}"
}

resource "aws_lb" "kubernetes_control_plane" {
  name = "kubernetes"
  internal = false
  load_balancer_type = "application"
  subnets = [ "${aws_subnet.kubernetes_control_plane.*.id}" ]
  security_groups = [ "${aws_security_group.kubernetes_control_plane_lb.id}" ]
}

resource "aws_lb_listener" "kubernetes_control_plane" {
  load_balancer_arn = "${aws_lb.kubernetes_control_plane.arn}"
  port = "${local.kubernetes_public_port}"
  protocol = "HTTP"
  default_action {
    target_group_arn = "${aws_lb_target_group.kubernetes_control_plane.arn}"
    type = "forward"
  }
}

resource "aws_route53_record" "kubernetes_public_address" {
  zone_id = "${data.aws_route53_zone.route53_zone_for_domain.zone_id}"
  name = "kubernetes"
  type = "CNAME"
  alias {
    name = "${aws_lb.kubernetes_control_plane.dns_name}"
    zone_id = "${aws_lb.kubernetes_control_plane.zone_id}"
    evaluate_target_health = true
  }
}

output "kubernetes_control_plane_dns_address" {
  value = "${aws_route53_record.kubernetes_public_address.fqdn}"
}
