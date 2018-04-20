# General variables
variable "name" {
  default = "aws-ecs-poc"
}

variable "aws_region" {
  default = "us-east-1"
}

variable "dockerimg" {
  default = "bctux/web-server-info"
}

variable "ami" {
  default = {
    us-east-1 = "ami-aff65ad2"
  }
}

# ECS Cluster
variable "instance_type" {
  default = "t2.micro"
}

variable "max_instances" {
  default = 2
}

variable "desired_instances" {
  default = 2
}

variable "lb_port" {
  default = 80
}

# Task definintion

variable "host_port" {
  default = 0
}

variable "docker_port" {
  default = 8080
}
