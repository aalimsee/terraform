#====================================
# Create Application Load Balancer
#====================================
resource "aws_lb" "public_alb" {
  name               = "${var.prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = aws_subnet.aalimsee_tf_public[*].id

  tags = {
    Name      = "${var.prefix}-alb"
    CreatedBy = var.createdByTerraform
  }
}

#====================================
# Target Group for Application Load Balancer
#====================================
resource "aws_lb_target_group" "public_tg" {
  name     = "${var.prefix}-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.aalimsee_tf_vpc.id

  health_check {
    interval            = 30
    timeout             = 5
    protocol            = "HTTP"
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 2
  }

  tags = {
    Name      = "${var.prefix}-alb-tg"
    CreatedBy = var.createdByTerraform
  }
}

#====================================
# Application Load Balancer - Listener
#====================================
resource "aws_lb_listener" "public_listener" {
  load_balancer_arn = aws_lb.public_alb.arn
  #port              = 80 # <<< update to 443 with HTTPS cert
  #protocol          = "HTTP" # <<< update to 443 with HTTPS cert
  port            = var.use_https ? 443 : 80
  protocol        = var.use_https ? "HTTPS" : "HTTP"
  certificate_arn = var.use_https ? aws_acm_certificate.https_cert.arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_tg.arn
  }
}



#====================================
# Create Network Load Balancer
#====================================
resource "aws_lb" "internal_nlb" {
  name               = "${var.prefix}-nlb"
  internal           = true
  load_balancer_type = "network"
  security_groups    = [aws_security_group.nlb.id] # <<< added
  subnets            = aws_subnet.aalimsee_tf_private[*].id

  tags = {
    Name      = "${var.prefix}-nlb"
    CreatedBy = var.createdByTerraform
  }
}

#====================================
# Target Group for Network Load Balancer
#====================================
resource "aws_lb_target_group" "internal_tg" {
  name     = "${var.prefix}-nlb-target-group"
  port     = 3128  # <<< changed to 3128
  protocol = "TCP" # <<< updated as TCP
  vpc_id   = aws_vpc.aalimsee_tf_vpc.id

  # <<< added this block 
  #health_check {
  #  interval            = 30
  #  timeout             = 5
  #  protocol            = "TCP" # <<< Need to be TCP by default. If not uncomment block
  #  path                = "/"
  #  healthy_threshold   = 3
  #  unhealthy_threshold = 2
  #}

  tags = {
    Name      = "${var.prefix}-nlb-tg"
    CreatedBy = var.createdByTerraform
  }
}

#====================================
# Network Load Balancer - Listener
#====================================
resource "aws_lb_listener" "internal_listener" {
  load_balancer_arn = aws_lb.internal_nlb.arn
  port              = 3128  # <<< changed to 3128
  protocol          = "TCP" # <<< Listener protocol 'HTTP' must be one of 'UDP, TCP, TCP_UDP, TLS'

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal_tg.arn
  }
}


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

  depends_on = [aws_launch_template.web_asg_lt] # <<< included for testing output display
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

#==========================================================
# Fetching Instance IDs from an Auto Scaling Group (Database)
#==========================================================
data "aws_autoscaling_group" "db_asg" {
  name = aws_autoscaling_group.db_asg.name
}

data "aws_instances" "db_asg_instances" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [data.aws_autoscaling_group.db_asg.name]
  }
}

output "asg_db_instance_ids" {
  value = data.aws_instances.db_asg_instances.ids

  depends_on = [aws_launch_template.db_asg_lt] # <<< included for testing output display
}

#==========================================================
# Registering Instances to an NLB with ASG (DB)
#==========================================================
resource "aws_lb_target_group_attachment" "db_targets" {
  count            = length(data.aws_instances.db_asg_instances.ids)
  target_group_arn = aws_lb_target_group.internal_tg.arn
  target_id        = data.aws_instances.db_asg_instances.ids[count.index]
  port             = 3128 # <<< match initial port during power up
}
