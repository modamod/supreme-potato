/* -------------------------------- Variables ------------------------------- */

variable "aws_profile" {}
variable "tf_key_name" {}
variable "tf_public_key_path" {}
variable "tf_private_key_path" {}
variable "vpc_cidr" {}
variable "my_ip" {}
variable "hostedzone" {}
variable "aws_region" {
  default = "us-east-1"
}

/* -------------------------------- Providers ------------------------------- */

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

/* ---------------------------------- Data ---------------------------------- */
data "aws_availability_zones" "azs" {}
data "aws_route53_zone" "primary" {
  name = var.hostedzone
}

data "aws_ami" "win-server12" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2012-R2_*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

/* -------------------------------- Resources ------------------------------- */

#This uses the default VPC.  It WILL NOT delete it on destroy.
# NETWORKING #
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = "true"

}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

}

resource "aws_subnet" "public_subnet1" {
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 2)
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = "true"
  availability_zone       = data.aws_availability_zones.azs.names[0]

}

resource "aws_subnet" "public_subnet2" {
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 3)
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = "true"
  availability_zone       = data.aws_availability_zones.azs.names[1]

}

# ROUTING #
resource "aws_route_table" "rtb" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta-public_subnet1" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.rtb.id
}

resource "aws_route_table_association" "rta-public_subnet2" {
  subnet_id      = aws_subnet.public_subnet2.id
  route_table_id = aws_route_table.rtb.id
}

resource "aws_security_group" "private_sg" {
  name        = "private_sg"
  description = "Private sg that allows all traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_security_group" "public_sg" {
  name        = "public_sg"
  description = "Allow ports for our servers"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["196.231.1.244/32"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "tf_key_pair" {
  key_name   = var.tf_key_name
  public_key = file(var.tf_public_key_path)
}

resource "aws_instance" "srv01" {
  ami                    = data.aws_ami.win-server12.id
  subnet_id              = aws_subnet.public_subnet1.id
  instance_type          = "t3.medium"
  key_name               = var.tf_key_name
  vpc_security_group_ids = [aws_security_group.public_sg.id, aws_security_group.private_sg.id]
}
resource "aws_route53_record" "dns_srv01" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "srv01"
  type    = "A"
  ttl     = "30"
  records = [aws_instance.srv01.public_ip]
  depends_on = [
    aws_instance.srv01
  ]
}
resource "aws_instance" "srv02" {
  ami                    = data.aws_ami.win-server12.id
  subnet_id              = aws_subnet.public_subnet1.id
  instance_type          = "t3.medium"
  key_name               = var.tf_key_name
  vpc_security_group_ids = [aws_security_group.public_sg.id, aws_security_group.private_sg.id]
}
resource "aws_route53_record" "dns_srv02" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "srv02"
  type    = "A"
  ttl     = "30"
  records = [aws_instance.srv02.public_ip]
  depends_on = [
    aws_instance.srv02
  ]
}

/* --------------------------------- Output --------------------------------- */

output "win_srv01_id" {
  value = aws_instance.srv01.id
}
output "win_srv01_dns" {
  value = "${aws_route53_record.dns_srv01.name}.${data.aws_route53_zone.primary.name}"
}
output "win_srv02_id" {
  value = aws_instance.srv02.id
}
output "win_srv02_dns" {
  value = "${aws_route53_record.dns_srv02.name}.${data.aws_route53_zone.primary.name}"
}
