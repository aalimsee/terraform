
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

resource "aws_route_table" "aalimsee_tf_public" { # <<< why aalimsee_tf_public is used
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

resource "aws_route_table_association" "aalimsee_tf_public" { # <<< why aalimsee_tf_public is used
  count          = 3
  subnet_id      = aws_subnet.aalimsee_tf_public[count.index].id
  route_table_id = aws_route_table.aalimsee_tf_public.id
}
