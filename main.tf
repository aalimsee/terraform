provider "aws" {
  region = "us-east-1"
}

# Create a VPC
resource "aws_vpc" "aalimsee_tf_main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "aalimsee-tf-vpc"
  }
}

# Create Public Subnets in 3 Availability Zones
resource "aws_subnet" "aalimsee_tf_public" {
  count                   = 3
  vpc_id                  = aws_vpc.aalimsee_tf_main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "aalimsee-tf-public-subnet-${count.index + 1}"
  }
}

# Create Private Subnets in 3 Availability Zones
resource "aws_subnet" "aalimsee_tf_private" {
  count             = 3
  vpc_id            = aws_vpc.aalimsee_tf_main.id
  cidr_block        = "10.0.${count.index + 4}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "aalimsee-tf-private-subnet-${count.index + 1}"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "aalimsee_tf_igw" {
  vpc_id = aws_vpc.aalimsee_tf_main.id

  tags = {
    Name = "aalimsee-tf-igw"
  }
}

# Create a Route Table for the Public Subnets
resource "aws_route_table" "aalimsee_tf_public" {
  vpc_id = aws_vpc.aalimsee_tf_main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.aalimsee_tf_igw.id
  }

  tags = {
    Name = "aalimsee-tf-public-route-table"
  }
}

# Associate Route Table with Public Subnets
resource "aws_route_table_association" "aalimsee_tf_public" {
  count          = 3
  subnet_id      = aws_subnet.aalimsee_tf_public[count.index].id
  route_table_id = aws_route_table.aalimsee_tf_public.id
}

# Create a Web Security Group
resource "aws_security_group" "aalimsee_tf_web_sg" {
  name = "aalimsee-tf-web-sg"
  vpc_id = aws_vpc.aalimsee_tf_main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "aalimsee-tf-web-sg"
  }
}

# Create a Database Security Group
resource "aws_security_group" "aalimsee_tf_db_sg" {
  name = "aalimsee-tf-db-sg"
  vpc_id = aws_vpc.aalimsee_tf_main.id

  # Allow NLB to connect to DB on port 3306
  ingress {
    from_port         = 3306
    to_port           = 3306
    protocol          = "tcp"
    security_groups   = [aws_security_group.aalimsee_tf_nlb_sg.id]
    description       = "Allow NLB to access DB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "aalimsee-tf-db-sg"
  }
}


# Create a Security Group for NLB
resource "aws_security_group" "aalimsee_tf_nlb_sg" {
  name = "aalimsee-tf-nlb-sg"
  vpc_id = aws_vpc.aalimsee_tf_main.id

  # Allow inbound traffic from the web ASG to the NLB
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic to NLB"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "aalimsee-tf-nlb-sg"
  }
}



# Create an Application Load Balancer
resource "aws_lb" "aalimsee_tf_alb" {
  name               = "aalimsee-tf-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.aalimsee_tf_web_sg.id]
  subnets            = aws_subnet.aalimsee_tf_public[*].id

  tags = {
    Name = "aalimsee-tf-alb"
  }
}

# Create Target Group for ALB
resource "aws_lb_target_group" "aalimsee_tf_tg" {
  name     = "aalimsee-tf-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.aalimsee_tf_main.id

  tags = {
    Name = "aalimsee-tf-target-group"
  }
}

# Create Listener for ALB
resource "aws_lb_listener" "aalimsee_tf_listener" {
  load_balancer_arn = aws_lb.aalimsee_tf_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aalimsee_tf_tg.arn
  }
}


# Reference the existing Route 53 Hosted Zone
data "aws_route53_zone" "aalimsee_tf_existing_zone" {
  name = "sctp-sandbox.com" # Replace with your exact domain
}

# Route 53 Record for Web Load Balancer
resource "aws_route53_record" "aalimsee_tf_web_alb" {
  zone_id = data.aws_route53_zone.aalimsee_tf_existing_zone.id
  name    = "aalimsee-web-tf.sctp-sandbox.com" # Subdomain for the web service
  type    = "A"
  alias {
    name                   = aws_lb.aalimsee_tf_web_alb.dns_name
    zone_id                = aws_lb.aalimsee_tf_web_alb.zone_id
    evaluate_target_health = true
  }

  tags = {
    Name = "aalimsee-tf-web-alb-record"
  }
}

# Create a Network Load Balancer for Database
resource "aws_lb" "aalimsee_tf_db_nlb" {
  name               = "aalimsee-tf-db-nlb"
  internal           = true # Internal NLB for private communication
  load_balancer_type = "network"
  subnets            = aws_subnet.aalimsee_tf_private[*].id

  tags = {
    Name = "aalimsee-tf-db-nlb"
  }
}

# Create Target Group for Database NLB
resource "aws_lb_target_group" "aalimsee_tf_db_tg" {
  name        = "aalimsee-tf-db-target-group"
  port        = 3306 # Database port (MySQL)
  protocol    = "TCP" # NLB uses TCP for DB traffic
  vpc_id      = aws_vpc.aalimsee_tf_main.id

  health_check {
    protocol            = "TCP" # Health check uses TCP
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "aalimsee-tf-db-tg"
  }
}

# Create Listener for Database Traffic
resource "aws_lb_listener" "aalimsee_tf_db_listener" {
  load_balancer_arn = aws_lb.aalimsee_tf_db_nlb.arn
  port              = 3306
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aalimsee_tf_db_tg.arn
  }
}



# Auto Scaling Launch Template
resource "aws_launch_template" "aalimsee_tf_web_asg_lt" {
  name          = "aalimsee-tf-web-launch-template"
  image_id      = "ami-05576a079321f21f8"
  instance_type = "t2.micro"
 
  metadata_options {
    http_tokens        = "optional"  # Allows both IMDSv1 and IMDSv2
    http_endpoint      = "enabled"   # Enables access to the metadata service
    http_put_response_hop_limit = 2   # Optional, sets the hop limit for metadata requests
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

  key_name      = "aalimsee-keypair" # Updated here
  vpc_security_group_ids = [
    aws_security_group.aalimsee_tf_web_sg.id
  ]

  tags = {
    Name = "aalimsee-tf-launch-template"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "aalimsee_tf_web_asg" {
  name    = "aalimsee-tf-web-asg" # Add this line to define the ASG name
  
  launch_template {
    id      = aws_launch_template.aalimsee_tf_web_asg_lt.id
    version = "$Latest"
  }

  min_size            = 2 
  max_size            = 5
  desired_capacity    = 2
  vpc_zone_identifier = aws_subnet.aalimsee_tf_public[*].id

  target_group_arns = [
    aws_lb_target_group.aalimsee_tf_tg.arn
  ]

  tag {
    key                 = "Name"
    value               = "aalimsee-tf-web-asg"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}



# Launch Template for DB Instances
resource "aws_launch_template" "aalimsee_tf_db_asg_lt" {
  name          = "aalimsee-tf-db-launch-template"
  image_id      = "ami-05576a079321f21f8" # Same as the web launch template
  instance_type = "t2.micro"
  key_name      = "aalimsee-keypair"
  vpc_security_group_ids = [
    aws_security_group.aalimsee_tf_db_sg.id
  ]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "aalimsee-tf-db-asg-instance"
    }
  }
}

# Auto Scaling Group for DB Instances
resource "aws_autoscaling_group" "aalimsee_tf_db_asg" {
  name    = "aalimsee-tf-db-asg" # Add this line to define the ASG name
 
  launch_template {
    id      = aws_launch_template.aalimsee_tf_db_asg_lt.id
    version = "$Latest"
  }

  min_size             = 2   # Minimum number of DB instances
  max_size             = 5   # Maximum number of DB instances
  desired_capacity     = 2   # Desired number of DB instances
  vpc_zone_identifier  = aws_subnet.aalimsee_tf_private[*].id # Private subnets for database
  health_check_type    = "EC2"
  health_check_grace_period = 300

  target_group_arns = [
    aws_lb_target_group.aalimsee_tf_db_tg.arn
  ]

  tag {
      key                 = "Name"
      value               = "aalimsee-tf-db-asg"
      propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}




# Data source to fetch availability zones
data "aws_availability_zones" "available" {}

