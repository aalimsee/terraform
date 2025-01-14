provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "seconday-region"
  region = "ap-southeast-1"
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "aalimsee_tf_main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = "${var.prefix}-vpc"
    CreatedBy = "${var.createdByTerraform}"
  }
}

resource "aws_subnet" "aalimsee_tf_public" {
  count                   = 3
  vpc_id                  = aws_vpc.aalimsee_tf_main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name      = "${var.prefix}-public-subnet-${count.index + 1}"
    CreatedBy = "${var.createdByTerraform}"
  }
}

resource "aws_subnet" "aalimsee_tf_private" {
  count             = 3
  vpc_id            = aws_vpc.aalimsee_tf_main.id
  cidr_block        = "10.0.${count.index + 4}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name      = "${var.prefix}-private-subnet-${count.index + 1}"
    CreatedBy = "${var.createdByTerraform}"
  }
}

resource "aws_internet_gateway" "aalimsee_tf_igw" {
  vpc_id = aws_vpc.aalimsee_tf_main.id

  tags = {
    Name      = "${var.prefix}-igw"
    CreatedBy = "${var.createdByTerraform}"
  }
}

resource "aws_route_table" "aalimsee_tf_public" {
  vpc_id = aws_vpc.aalimsee_tf_main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.aalimsee_tf_igw.id
  }

  tags = {
    Name      = "${var.prefix}-public-route-table"
    CreatedBy = "${var.createdByTerraform}"
  }
}

resource "aws_route_table_association" "aalimsee_tf_public" {
  count          = 3
  subnet_id      = aws_subnet.aalimsee_tf_public[count.index].id
  route_table_id = aws_route_table.aalimsee_tf_public.id
}

resource "aws_security_group" "web" {
  name   = "${var.prefix}-web-sg"
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
    Name      = "${var.prefix}-web-sg"
    CreatedBy = "${var.createdByTerraform}"
  }
}

resource "aws_security_group" "nlb" {
  name   = "${var.prefix}-nlb-sg"
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
    Name      = "${var.prefix}-nlb-sg"
    CreatedBy = "${var.createdByTerraform}"
  }
}

resource "aws_launch_template" "web_asg_lt" {
  name          = "${var.prefix}-web-launch-template"
  image_id      = "ami-05576a079321f21f8"
  instance_type = "t2.micro"
  key_name      = "${var.key-pair}"
  update_default_version = true 
  description   = "${var.createdByTerraform}"

  metadata_options {
    http_tokens                 = "optional" # Allows both IMDSv1 and IMDSv2
    http_endpoint               = "enabled"  # Enables access to the metadata service
    http_put_response_hop_limit = 2          # Optional, sets the hop limit for metadata requests
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
    Name      = "${var.prefix}-web-instance"
    CreatedBy = "${var.createdByTerraform}"
  }
}

resource "aws_autoscaling_group" "web_asg" {
  name = "${var.prefix}-web-asg"
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
    value               = "${var.prefix}-web-asg"
    propagate_at_launch = true
  }
}

resource "aws_launch_template" "db_asg_lt" {
  name          = "${var.prefix}-db-launch-template"
  image_id      = "ami-05576a079321f21f8"
  instance_type = "t2.micro"
  key_name      = "aalimsee-keypair"
  update_default_version = true
  description   = "${var.createdByTerraform}"

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "${var.prefix}-db-instance"
      CreatedBy = "${var.createdByTerraform}"
    }
  }
}

resource "aws_autoscaling_group" "db_asg" {
  name = "${var.prefix}-db-asg"
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
    value               = "${var.prefix}-db-asg"
    propagate_at_launch = true
  }
}

resource "aws_lb" "public_alb" {
  name               = "${var.prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = aws_subnet.aalimsee_tf_public[*].id

  tags = {
    Name      = "${var.prefix}-alb"
    CreatedBy = "${var.createdByTerraform}"
  }
}

resource "aws_lb_target_group" "public_tg" {
  name     = "${var.prefix}-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.aalimsee_tf_main.id

  health_check {
    interval            = 30
    timeout             = 5
    protocol            = "HTTP"
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 2
  }

  tags = {
    Name      = "${var.prefix}-alb-target-group"
    CreatedBy = "${var.createdByTerraform}"
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
  name               = "${var.prefix}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.aalimsee_tf_private[*].id

  tags = {
    Name      = "${var.prefix}-nlb"
    CreatedBy = "${var.createdByTerraform}"
  }
}

resource "aws_lb_target_group" "internal_tg" {
  name     = "${var.prefix}-nlb-target-group"
  port     = 3306
  protocol = "TCP"
  vpc_id   = aws_vpc.aalimsee_tf_main.id

  tags = {
    Name      = "${var.prefix}-nlb-target-group"
    CreatedBy = "${var.createdByTerraform}"
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

#==========================================================
# Reference the existing Route 53 Hosted Zone
data "aws_route53_zone" "existing_zone" {
  name = "sctp-sandbox.com" # Replace with your exact domain
}

# Route 53 Record for Web Load Balancer
resource "aws_route53_record" "public_alb" {
  zone_id = data.aws_route53_zone.existing_zone.id
  name    = "aalimsee-tf-web" # Subdomain for the web service
  type    = "A"
  alias {
    name                   = aws_lb.public_alb.dns_name
    zone_id                = aws_lb.public_alb.zone_id
    evaluate_target_health = true
  }
}
#==========================================================

#==========================================================
# Fetching Instance IDs from an Auto Scaling Group
#==========================================================
data "aws_autoscaling_group" "web_asg" {
  name = aws_autoscaling_group.web_asg.name
}

data "aws_instances" "asg_instances" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [data.aws_autoscaling_group.web_asg.name]
  }
}

output "asg_instance_ids" {
  value = data.aws_instances.asg_instances.ids
}

#==========================================================
# Registering Instances to an ALB with ASG
#==========================================================
resource "aws_lb_target_group_attachment" "targets" {
  count            = length(data.aws_instances.asg_instances.ids)
  target_group_arn = aws_lb_target_group.public_tg.arn
  target_id        = data.aws_instances.asg_instances.ids[count.index]
  port             = 80
}
#==========================================================
