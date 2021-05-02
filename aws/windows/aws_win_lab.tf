/* -------------------------------- Variables ------------------------------- */

variable "tf_key_name" {}
variable "tf_public_key_path" {}
variable "tf_private_key_path" {}
variable "vpc_cidr" {}
variable "my_ip" {}
variable "instance_count" {}
variable "subnet_count" {}
variable "hostedzone" {}
variable "aws_profile" {
  default = "acg"
}
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
    values = ["Windows_Server-2012-R2*-64Bit-Base-*"]
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

// data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "instance-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy" "admin_policy" {
  arn = "arn:aws:iam::aws:policy/AdministratorAccess"
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

resource "aws_subnet" "public_subnet" {
  count                   = var.subnet_count
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = "true"
  availability_zone       = data.aws_availability_zones.azs.names[count.index]

}

# ROUTING #
resource "aws_route_table" "rtb" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta-public_subnet" {
  count          = var.subnet_count
  subnet_id      = aws_subnet.public_subnet[count.index].id
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
    cidr_blocks = ["${var.my_ip}/32"]
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


resource "aws_iam_role" "admin_instance" {
  name = "admin_instance"
  path = "/"
  force_detach_policies = true
  assume_role_policy = data.aws_iam_policy_document.instance-assume-role-policy.json
}

resource "aws_iam_role_policy_attachment" "admin_policy_attach" {
  role       = aws_iam_role.admin_instance.name
  policy_arn = data.aws_iam_policy.admin_policy.arn
}

resource "aws_iam_instance_profile" "admin_instance" {
  name = "admin_instance"
  role = aws_iam_role.admin_instance.name
}

resource "aws_instance" "srv" {
  count                  = var.instance_count
  ami                    = data.aws_ami.win-server12.id
  subnet_id              = aws_subnet.public_subnet[count.index % var.subnet_count].id
  instance_type          = "t3.medium"
  key_name               = var.tf_key_name
  vpc_security_group_ids = [aws_security_group.public_sg.id, aws_security_group.private_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.admin_instance.id
  tags = {
    Name = "srv${count.index}"
  }
}
resource "aws_route53_record" "dns_srv" {
  count           = var.instance_count
  zone_id         = data.aws_route53_zone.primary.zone_id
  name            = "srv${count.index}"
  type            = "A"
  ttl             = "30"
  records         = [aws_instance.srv[count.index].public_ip]
  allow_overwrite = true
  depends_on = [
    aws_instance.srv
  ]
}

/* --------------------------------- Output --------------------------------- */

output "aws_route53_record_public_dns" {
  value = aws_route53_record.dns_srv[*].fqdn
}
output "aws_instance_id" {
  value = aws_instance.srv[*].id
}
