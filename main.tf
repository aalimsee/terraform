
data "aws_availability_zones" "available" {}

#====================================
# Launch Template Web for ASG
#====================================
resource "aws_launch_template" "web_asg_lt" {
  name                   = "${var.prefix}-web-launch-template"
  image_id               = "ami-05576a079321f21f8"
  instance_type          = "t2.micro"
  key_name               = "${var.key-pair}"
  update_default_version = true 
  description            = "${var.createdByTerraform}"

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

#====================================
# Auto Scaling Group Web
#====================================
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

#====================================
# Launch Template DB
#====================================
resource "aws_launch_template" "db_asg_lt" {
  name          = "${var.prefix}-db-launch-template"
  image_id      = "ami-05576a079321f21f8"
  instance_type = "t2.micro"
  key_name      = "aalimsee-keypair"
  update_default_version = true
  description   = "${var.createdByTerraform}"

    # <<< add this block
    user_data = base64encode(<<-EOF
      #!/bin/bash
      # Update system
      sudo yum update -y
      # Install Squid proxy
      sudo yum install squid -y
      # Configure Squid to allow traffic from the VPC CIDR
      sudo echo "acl allowed_network src 10.0.0.0/16" >> /etc/squid/squid.conf
      sudo echo "http_access allow allowed_network" >> /etc/squid/squid.conf
      # Restart Squid to apply changes
      sudo systemctl enable squid
      sudo systemctl restart squid
      EOF
    )

  vpc_security_group_ids = [aws_security_group.nlb.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "${var.prefix}-db-instance"
      CreatedBy = "${var.createdByTerraform}"
    }
  }
}

#====================================
# Auto Scaling Group DB
#====================================
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

    timeouts {
    #create = "1h"  
    update = "30m"
    delete = "10m"
    }
}
