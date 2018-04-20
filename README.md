# terraform-ecs-poc
A Terraform PoC running a web app using ECS in two availability zones fronted by an ALB.

## Prerequisites
- Terraform
- AWS Access
- AWS CLI working

## How-to
Set your AWS credentials in *~/.aws/credentials*
```
aws_access_key_id = 
aws_secret_access_key =
```

Clone the repository.
```
$ git clone https://github.com/bcarlsson/terraform-ecs-poc.git
```

Initialize the cloned directory.
```
$ cd terraform-ecs-poc
$ terraform init
```

Verify the Terraform configuration.
```
$ terraform plan
```

If everything seems ok, go ahead and apply configuration to AWS.
```
$ terraform apply
```