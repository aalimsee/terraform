# Define Provider
provider "aws" {
  region = var.region
}

# Variables
variable "region" {
  default = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "key_name" {
  default = "aalimsee-keypair"
}

variable "ami_id" {
  default = "ami-05576a079321f21f8"
}

variable "public_subnet_cidr_blocks" {
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidr_blocks" {
  default = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "az_count" {
  default = 3
}

# Data source to fetch availability zones
data "aws_availability_zones" "available" {}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "aalimsee-tf-vpc"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_blocks[count.index]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "aalimsee-tf-public-subnet-${count.index + 1}"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = var.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "aalimsee-tf-private-subnet-${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "aalimsee-tf-igw"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "aalimsee-tf-public-route-table"
  }
}

# Associate Route Table with Public Subnets
resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Group for Web Instances
resource "aws_security_group" "web" {
  name   = "aalimsee-tf-web-sg"
  vpc_id = aws_vpc.main.id

  ingress = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  egress = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = {
    Name = "aalimsee-tf-web-sg"
  }
}

# Security Group for Database Instances
resource "aws_security_group" "db" {
  name   = "aalimsee-tf-db-sg"
  vpc_id = aws_vpc.main.id

  ingress = [
    {
      from_port       = 3306
      to_port         = 3306
      protocol        = "tcp"
      security_groups = [aws_security_group.nlb.id]
    }
  ]

  egress = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = {
    Name = "aalimsee-tf-db-sg"
  }
}

# Security Group for NLB
resource "aws_security_group" "nlb" {
  name   = "aalimsee-tf-nlb-sg"
  vpc_id = aws_vpc.main.id

  ingress = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  egress = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = {
    Name = "aalimsee-tf-nlb-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "alb" {
  name               = "aalimsee-tf-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "aalimsee-tf-alb"
  }
}

# Target Group for ALB
resource "aws_lb_target_group" "alb_tg" {
  name     = "aalimsee-tf-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  tags = {
    Name = "aalimsee-tf-target-group"
  }
}

# Listener for ALB
resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg.arn
  }
}

# Launch Template for Web Instances
resource "aws_launch_template" "web" {
  name          = "aalimsee-tf-web-launch-template"
  image_id      = var.ami_id
  instance_type = "t2.micro"
  key_name      = var.key_name

  metadata_options {
    http_tokens               = "optional"
    http_endpoint             = "enabled"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
yum update -y
yum install httpd -y
echo "<h1>Hello from Application 1, Aaron Lim</h1>" | sudo tee /var/www/html/index.html
echo "<h1>Hello from Instance $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</h1>" | sudo tee -a /var/www/html/index.html
systemctl start httpd
systemctl enable httpd
EOF
  )

  vpc_security_group_ids = [aws_security_group.web.id]

  tags = {
    Name = "aalimsee-tf-web-launch-template"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group for Web Instances
resource "aws_autoscaling_group" "web" {
  name                 = "aalimsee-tf-web-asg"
  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }
  min_size            = 2
  max_size            = 5
  desired_capacity    = 2
  vpc_zone_identifier = aws_subnet.public[*].id

  target_group_arns = [aws_lb_target_group.alb_tg.arn]

  tag {
    key                 = "Name"
    value               = "aalimsee-tf-web-asg"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Network Load Balancer for Database
resource "aws_lb" "db_nlb" {
  name               = "aalimsee-tf-db-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id

  tags = {
    Name = "aalimsee-tf-db-nlb"
  }
}

# Target Group for Database NLB
resource "aws_lb_target_group" "db_tg" {
  name        = "aalimsee-tf-db-target-group"
  port        = 3306
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id

  health_check {
    protocol            = "TCP"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "aalimsee-tf-db-tg"
  }
}

# Listener for Database NLB
resource "aws_lb_listener" "db_listener" {
  load_balancer_arn = aws_lb.db_nlb.arn
  port              = 3306
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.db_tg.arn
  }
}

# Launch Template for Database Instances
resource "aws_launch_template" "db" {
  name          = "aalimsee-tf-db-launch-template"
  image_id      = var.ami_id
  instance_type = "t2.micro"
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.db.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "aalimsee-tf-db-instance"
    }
  }
}

# Auto Scaling Group for Database Instances
resource "aws_autoscaling_group" "db" {
  name                 = "aalimsee-tf-db-asg"
  launch_template {
    id      = aws_launch_template.db.id
    version = "$Latest"
  }
  min_size            = 2
  max_size            = 5
  desired_capacity    = 2
}

