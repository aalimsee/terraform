# Create a NAT Gateway in the Public Subnet
  resource "aws_nat_gateway" "aalimsee_tf_nat" {
  allocation_id = aws_eip.aalimsee_tf_nat.id
  subnet_id     = aws_subnet.aalimsee_tf_public[0].id

  tags = {
    #Name = "aalimsee-tf-nat-gateway"
    Name = "${var.prefix}-nat-gateway"
    CreatedBy = "Managed by Terraform" # <<<
    }
}

# Create an Elastic IP for the NAT Gateway
resource "aws_eip" "aalimsee_tf_nat" {
  #vpc = true
  domain = "vpc"

  tags = {
    Name = "${var.prefix}-eip-nat"
    CreatedBy = "Managed by Terraform" # <<<
  }
}

resource "aws_route_table" "aalimsee_tf_private_route" {
  vpc_id = aws_vpc.aalimsee_tf_main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.aalimsee_tf_nat.id
  }

  tags = {
    #Name = "aalimsee-tf-private-route"
    Name = "${var.prefix}-private-route"
    }
}

resource "aws_route_table_association" "aalimsee_tf_private_route_assoc" {
  count          = 3
  subnet_id      = aws_subnet.aalimsee_tf_private[count.index].id
  route_table_id = aws_route_table.aalimsee_tf_private_route.id
}