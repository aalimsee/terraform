provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "aalimsee_tf_main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name       = "aalimsee-tf-vpc"
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_subnet" "aalimsee_tf_public" {
  count                   = 3
  vpc_id                  = aws_vpc.aalimsee_tf_main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name       = "aalimsee-tf-public-subnet-${count.index + 1}"
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_subnet" "aalimsee_tf_private" {
  count             = 3
  vpc_id            = aws_vpc.aalimsee_tf_main.id
  cidr_block        = "10.0.${count.index + 4}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name       = "aalimsee-tf-private-subnet-${count.index + 1}"
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_internet_gateway" "aalimsee_tf_igw" {
  vpc_id = aws_vpc.aalimsee_tf_main.id

  tags = {
    Name       = "aalimsee-tf-igw"
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_route_table" "aalimsee_tf_public" {
  vpc_id = aws_vpc.aalimsee_tf_main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.aalimsee_tf_igw.id
  }

  tags = {
    Name       = "aalimsee-tf-public-route-table"
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_route_table_association" "aalimsee_tf_public" {
  count          = 3
  subnet_id      = aws_subnet.aalimsee_tf_public[count.index].id
  route_table_id = aws_route_table.aalimsee_tf_public.id
}

resource "aws_security_group" "web" {
  name   = "aalimsee-tf-web-sg"
  vpc_id = aws_vpc.aalimsee_tf_main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name       = "aalimsee-tf-web-sg"
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_security_group" "nlb" {
  name   = "aalimsee-tf-nlb-sg"
  vpc_id = aws_vpc.aalimsee_tf_main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic to NLB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name       = "aalimsee-tf-nlb-sg"
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_launch_template" "web_asg_lt" {
  name          = "aalimsee-tf-web-launch-template"
  image_id      = "ami-05576a079321f21f8"
  instance_type = "t2.micro"
  key_name      = "aalimsee-keypair"

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
    Name       = "aalimsee-tf-web-instance"
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_autoscaling_group" "web_asg" {
  launch_template {
    id      = aws_launch_template.web_asg_lt.id
    version = "$Latest"
  }

  min_size            = 2
  max_size            = 5
  desired_capacity    = 2
  vpc_zone_identifier = aws_subnet.aalimsee_tf_public[*].id

  tag {
    key                 = "Name"
    value               = "aalimsee-tf-web-asg"
    propagate_at_launch = true
  }

  tags = {
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_launch_template" "db_asg_lt" {
  name          = "aalimsee-tf-db-launch-template"
  image_id      = "ami-05576a079321f21f8"
  instance_type = "t2.micro"
  key_name      = "aalimsee-keypair"

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name       = "aalimsee-tf-db-instance"
      CreatedBy  = "aalimsee-tf"
    }
  }
}

resource "aws_autoscaling_group" "db_asg" {
  launch_template {
    id      = aws_launch_template.db_asg_lt.id
    version = "$Latest"
  }

  min_size            = 2
  max_size            = 5
  desired_capacity    = 2
  vpc_zone_identifier = aws_subnet.aalimsee_tf_private[*].id

  tag {
    key                 = "Name"
    value               = "aalimsee-tf-db-asg"
    propagate_at_launch = true
  }

  tags = {
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_lb" "public_alb" {
  name               = "aalimsee-tf-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = aws_subnet.aalimsee_tf_public[*].id

  tags = {
    Name       = "aalimsee-tf-alb"
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_lb_target_group" "public_tg" {
  name     = "aalimsee-tf-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.aalimsee_tf_main.id

  tags = {
    Name       = "aalimsee-tf-target-group"
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_lb_listener" "public_listener" {
  load_balancer_arn = aws_lb.public_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_tg.arn
  }
}

resource "aws_lb" "internal_nlb" {
  name               = "aalimsee-tf-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.aalimsee_tf_private[*].id

  tags = {
    Name       = "aalimsee-tf-nlb"
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_lb_target_group" "internal_tg" {
  name     = "aalimsee-tf-nlb-target-group"
  port     = 3306
  protocol = "TCP"
  vpc_id   = aws_vpc.aalimsee_tf_main.id

  tags = {
    Name       = "aalimsee-tf-nlb-target-group"
    CreatedBy  = "aalimsee-tf"
  }
}

resource "aws_lb_listener" "internal_listener" {
  load_balancer_arn = aws_lb.internal_nlb.arn
  port              = 3306
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal_tg.arn
  }
}
