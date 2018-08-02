resource "aws_key_pair" "all_instances" {
  key_name = "kubernetes_cluster_${var.environment_name}"
  public_key = "${var.kubernetes_cluster_public_key}"
}

resource "aws_spot_instance_request" "etcd_cluster" {
  count = "${var.number_of_masters_per_control_plane}"
  availability_zone = "${element(data.aws_availability_zones.available_to_this_account.names,count.index)}"
  subnet_id = "${element(aws_subnet.kubernetes_control_plane.*.id, count.index)}"
  ami = "${var.etcd_node_ami}"
  instance_type = "${var.etcd_node_instance_type}"
  key_name = "${aws_key_pair.all_instances.key_name}"
  security_groups = [ "${aws_security_group.kubernetes_clusters.id}" ]
  associate_public_ip_address = true
  user_data = "${data.template_file.etcd_node_user_data.rendered}"
  root_block_device {
    volume_type = "gp2"
    volume_size = 32
    delete_on_termination = true
  }
  spot_price = "${var.etcd_nodes_spot_price}"
  wait_for_fulfillment = true
  tags = "${var.etcd_tags}"
}

resource "aws_spot_instance_request" "kubernetes_control_plane" {
  count = "${var.number_of_masters_per_control_plane}"
  availability_zone = "${element(data.aws_availability_zones.available_to_this_account.names,count.index)}"
  subnet_id = "${element(aws_subnet.kubernetes_control_plane.*.id, count.index)}"
  ami = "${var.kubernetes_node_ami}"
  instance_type = "${var.kubernetes_node_instance_type}"
  key_name = "${aws_key_pair.all_instances.key_name}"
  security_groups = [ "${aws_security_group.kubernetes_clusters.id}" ]
  associate_public_ip_address = true
  user_data = "${data.template_file.kubernetes_controller_user_data.rendered}"
  root_block_device {
    volume_type = "gp2"
    volume_size = 32
    delete_on_termination = true
  }
  spot_price = "${var.kubernetes_nodes_spot_price}"
  wait_for_fulfillment = true
  tags = "${var.kubernetes_controller_tags}"
  source_dest_check = false
}

resource "aws_spot_instance_request" "kubernetes_workers" {
  count = "${var.number_of_workers_per_cluster}"
  availability_zone = "${element(data.aws_availability_zones.available_to_this_account.names,count.index)}"
  subnet_id = "${element(aws_subnet.kubernetes_workers.*.id, count.index)}"
  ami = "${var.kubernetes_node_ami}"
  instance_type = "${var.kubernetes_node_instance_type}"
  key_name = "${aws_key_pair.all_instances.key_name}"
  security_groups = [ "${aws_security_group.kubernetes_clusters.id}" ]
  associate_public_ip_address = true
  user_data = "${data.template_file.kubernetes_worker_user_data.rendered}"
  root_block_device {
    volume_type = "gp2"
    volume_size = 32
    delete_on_termination = true
  }
  spot_price = "${var.kubernetes_nodes_spot_price}"
  wait_for_fulfillment = true
  tags = "${var.kubernetes_worker_tags}"
  source_dest_check = false
}

resource "null_resource" "wait_for_worker_instances_to_be_fulfilled" {
  provisioner "local-exec" {
    command = "sleep ${var.seconds_to_wait_for_worker_fulfillment}"
  }
  triggers {
    instances_to_wait_on = "${join(",", aws_spot_instance_request.kubernetes_workers.*.id)}"
  }
}

resource "aws_route" "kubernetes_pods_within_workers" {
  depends_on = [ "null_resource.wait_for_worker_instances_to_be_fulfilled" ]
  count = "${var.number_of_workers_per_cluster}"
  route_table_id = "${aws_route_table.kubernetes_clusters.id}"
  destination_cidr_block = "${replace(var.kubernetes_pod_cidr_block, "/^([0-9]{1,3}.[0-9]{1,3}).*/", "$1.${count.index+1}.0/24")}"
  instance_id = "${aws_spot_instance_request.kubernetes_workers.*.spot_instance_id[count.index]}"
}
