resource "aws_iam_service_linked_role" "aws_spot" {
  aws_service_name = "spot.amazonaws.com"
}

resource "aws_iam_service_linked_role" "aws_spot_fleet" {
  aws_service_name = "spotfleet.amazonaws.com"
}

resource "aws_iam_role" "kubernetes_control_plane_spot_fleet" {
  name = "kubernetes_control_plane_spot_fleet_role"
  description = "IAM role to use for the spot fleet created for our k8s control plane."
  assume_role_policy = <<EOF
{  
   "Version":"2012-10-17",
   "Statement":[  
      {  
         "Sid":"",
         "Effect":"Allow",
         "Principal":{  
            "Service":"spotfleet.amazonaws.com"
         },
         "Action":"sts:AssumeRole"
      }
   ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "kubernetes_control_plane_spot_fleet" {
  role = "${aws_iam_role.kubernetes_control_plane_spot_fleet.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}
