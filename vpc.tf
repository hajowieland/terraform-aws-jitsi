resource "aws_vpc" "vpc" {
  cidr_block                       = var.vpc_cidr
  enable_dns_support               = true
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = var.ipv6

  tags = local.tags
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = local.tags
}


# --------------------------------------------------------------------------
# Public Subnets
# --------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = var.number_azs

  availability_zone = data.aws_availability_zones.available.names[count.index]
  vpc_id            = aws_vpc.vpc.id
  // For every new subnet group, increment the left side of the var.number_azs multiplicator (useful when defining more than a public subnet group)
  cidr_block = cidrsubnet(var.vpc_cidr, 4, 1 + (0 * var.number_azs) + count.index)

  tags = merge(local.tags, map("Name", "public-${data.aws_availability_zones.available.names[count.index]}"))
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  tags = local.tags

  lifecycle {
    ignore_changes = [route]
  }
}


resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "public_internet_gateway_ipv6" {
  count = var.ipv6 == true ? 1 : 0

  route_table_id              = aws_route_table.public.id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.igw.id
}


resource "aws_route_table_association" "public" {
  count = var.number_azs

  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}
