# Provider set to AWS.
provider "aws" {
  region = "${var.aws_region}"
}

# VPC with 2 subnets in 2 availibility zones.
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "${var.name}-vpc"
  cidr   = "10.100.0.0/16"

  public_subnets = [
    "10.100.101.0/24",
    "10.100.102.0/24",
  ]

  azs = [
    "us-east-1c",
    "us-east-1b",
  ]

  enable_nat_gateway = true
}

# Security group to allow all inbound traffic to the ALB.
resource "aws_security_group" "allow_all_inbound" {
  name_prefix = "${var.name}-${module.vpc.vpc_id}-"
  description = "Allow all inbound traffic"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress = {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group to allow all outbound traffic from the ALB and ECS.
resource "aws_security_group" "allow_all_outbound" {
  name_prefix = "${var.name}-${module.vpc.vpc_id}-"
  description = "Allow all outbound traffic"
  vpc_id      = "${module.vpc.vpc_id}"

  egress = {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group to allow all inbound and outbound traffic to and from the ALB and ECS.
resource "aws_security_group" "allow_cluster" {
  name_prefix = "${var.name}-${module.vpc.vpc_id}-"
  description = "Allow all traffic within cluster"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress = {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.100.0.0/16"]
  }

  egress = {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM role that has a trust relationship which allows to assume the role of EC2.
resource "aws_iam_role" "ecs" {
  name = "${var.name}_ecs"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF
}

# Policy attachment for the "ecs" role to provide access to the the ECS service.
resource "aws_iam_policy_attachment" "ecs_for_ec2" {
  name       = "${var.name}"
  roles      = ["${aws_iam_role.ecs.id}"]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# IAM role for the load balancer to have access to ECS.
resource "aws_iam_role" "ecs_alb" {
  name = "${var.name}_ecs_alb"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "",
        "Effect": "Allow",
        "Principal": {
          "Service": "ecs.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }
  EOF
}

# Policy attachment for the "ecs_alb" role.
resource "aws_iam_policy_attachment" "ecs_alb" {
  name       = "${var.name}_ecs_alb"
  roles      = ["${aws_iam_role.ecs_alb.id}"]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

# Container definitions using template file "task-definition.json.tmpl".
data "template_file" "task_definition" {
  template = "${file("task-definition.json.tmpl")}"

  vars {
    name        = "${var.name}"
    image       = "${var.dockerimg}"
    docker_port = "${var.docker_port}"
    host_port   = "${var.host_port}"
  }
}

# Create a task definition for ECS.
resource "aws_ecs_task_definition" "ecs_task" {
  family                = "${var.name}"
  container_definitions = "${data.template_file.task_definition.rendered}"
}

# ALB.
resource "aws_alb" "service_alb" {
  name     = "awsalb"
  internal = false
  subnets  = ["${module.vpc.public_subnets}"]

  security_groups = [
    "${aws_security_group.allow_all_inbound.id}",
    "${aws_security_group.allow_all_outbound.id}",
  ]
}

# ALB target group. 
resource "aws_alb_target_group" "alb_target_group" {
  vpc_id   = "${module.vpc.vpc_id}"
  port     = "${var.lb_port}"
  protocol = "HTTP"
}

# Setup ALB listening port and forwarding to "alb_target_group".
resource "aws_alb_listener" "alb_listener" {
  "default_action" {
    target_group_arn = "${aws_alb_target_group.alb_target_group.arn}"
    type             = "forward"
  }

  load_balancer_arn = "${aws_alb.service_alb.arn}"
  port              = "${var.lb_port}"
  protocol          = "HTTP"
}

# ECS cluster.
resource "aws_ecs_cluster" "cluster" {
  name = "${var.name}"
}

# ECS cluster service.
resource "aws_ecs_service" "ecs_service" {
  name            = "${var.name}"
  cluster         = "${aws_ecs_cluster.cluster.id}"
  task_definition = "${aws_ecs_task_definition.ecs_task.arn}"
  desired_count   = 5
  iam_role        = "${aws_iam_role.ecs_alb.arn}"

  depends_on                         = ["aws_alb_listener.alb_listener"]
  deployment_minimum_healthy_percent = 50

  load_balancer {
    target_group_arn = "${aws_alb_target_group.alb_target_group.arn}"
    container_name   = "${var.name}"
    container_port   = "${var.docker_port}"
  }
}

# IAM instance profile.
resource "aws_iam_instance_profile" "ecs" {
  name = "${var.name}"
  role = "${aws_iam_role.ecs.name}"
}

# Launch configuration for ECS cluster.
# user_data is used to make EC2 instances connect to the cluster.
resource "aws_launch_configuration" "ecs_cluster" {
  name                        = "${var.name}_cluster_conf"
  instance_type               = "${var.instance_type}"
  image_id                    = "${lookup(var.ami, var.aws_region)}"
  iam_instance_profile        = "${aws_iam_instance_profile.ecs.id}"
  associate_public_ip_address = false

  security_groups = [
    "${aws_security_group.allow_cluster.id}",
  ]

  user_data = "#!/bin/bash\necho ECS_CLUSTER=${aws_ecs_service.ecs_service.name} >> /etc/ecs/ecs.config"
}

# Autoscaling group for the cluster.
resource "aws_autoscaling_group" "ecs_cluster" {
  name                 = "${var.name}"
  vpc_zone_identifier  = ["${module.vpc.public_subnets}"]
  min_size             = 0
  max_size             = "${var.max_instances}"
  desired_capacity     = "${var.desired_instances}"
  launch_configuration = "${aws_launch_configuration.ecs_cluster.name}"
  health_check_type    = "EC2"
}

# Attach autoscaling group and target group.
resource "aws_autoscaling_attachment" "autoscaling" {
  alb_target_group_arn   = "${aws_alb_target_group.alb_target_group.arn}"
  autoscaling_group_name = "${aws_autoscaling_group.ecs_cluster.id}"
}
