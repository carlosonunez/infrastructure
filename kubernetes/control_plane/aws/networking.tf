resource "aws_vpc" "kubernetes_clusters" {
  cidr_block = "${var.cidr_block_for_kubernetes_clusters}"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = "${merge(local.aws_tags, var.kubernetes_cluster_vpc_tags)}"
}

resource "aws_internet_gateway" "kubernetes_clusters" {
  vpc_id = "${aws_vpc.kubernetes_clusters.id}"
  tags = "${merge(local.aws_tags, var.kubernetes_cluster_vpc_tags)}"
}

resource "aws_subnet" "kubernetes_clusters" {
  count = "${var.number_of_zones}"
  vpc_id = "${aws_vpc.kubernetes_clusters.id}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block = "${local.subnets.cidr_blocks.first}"
  map_public_ip_on_launch = true
  tags = "${merge(local.aws_tags, var.kubernetes_cluster_subnet_tags)}"
}

resource "aws_route_table" "kubernetes_clusters" {
  vpc_id = "${aws_vpc.kubernetes_clusters.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.kubernetes_clusters.id}"
  }
}

resource "aws_route_table_association" "kubernetes_clusters_subnet_link" {
  count = "${var.number_of_zones}"
  subnet_id = "${aws_subnet.kubernetes_clusters.*.id}"
  route_table_id = "${aws_route_table.kubernetes_clusters.id}"
}
