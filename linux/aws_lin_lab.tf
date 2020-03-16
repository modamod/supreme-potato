/* -------------------------------- Variables ------------------------------- */

variable "aws_profile" {}
variable "tf_key_name" {}
variable "tf_public_key_path" {}
variable "tf_private_key_path" {}
variable "vpc_cidr" {}
variable "acm_cert" {}
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

data "aws_ami" "aws-linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn-ami-hvm*"]
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
data "template_file" "init" {
  template = file("scripts/user_data.tpl")
}

data "template_cloudinit_config" "config" {
  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content      = data.template_file.init.rendered
  }

  part {
    content_type = "text/x-shellscript"
    content      = "baz"
  }

  part {
    content_type = "text/x-shellscript"
    content      = "ffbaz"
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

resource "aws_subnet" "private_subnet1" {
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 0)
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = "false"
  availability_zone       = data.aws_availability_zones.azs.names[0]

}

resource "aws_subnet" "private_subnet2" {
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = "false"
  availability_zone       = data.aws_availability_zones.azs.names[1]

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

resource "aws_eip" "eip1" {
  vpc = true
}

resource "aws_eip" "eip2" {
  vpc = true
}

resource "aws_nat_gateway" "ngw1" {
  allocation_id = aws_eip.eip1.id
  subnet_id     = aws_subnet.public_subnet1.id
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "ngw2" {
  allocation_id = aws_eip.eip2.id
  subnet_id     = aws_subnet.public_subnet2.id
  depends_on    = [aws_internet_gateway.igw]
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

resource "aws_route_table" "private_rtb1" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.ngw1.id
  }
}

resource "aws_route_table" "private_rtb2" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.ngw2.id
  }
}

resource "aws_route_table_association" "rta-private_subnet1" {
  subnet_id      = aws_subnet.private_subnet1.id
  route_table_id = aws_route_table.private_rtb1.id
}

resource "aws_route_table_association" "rta-private_subnet2" {
  subnet_id      = aws_subnet.private_subnet2.id
  route_table_id = aws_route_table.private_rtb2.id
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
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

resource "aws_instance" "server01" {
  ami                    = data.aws_ami.aws-linux.id
  subnet_id              = aws_subnet.public_subnet1.id
  instance_type          = "t3.medium"
  key_name               = var.tf_key_name
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  user_data_base64       = data.template_cloudinit_config.config.rendered
}

resource "aws_lb" "nlb" {
  name                       = "network-lb-tf"
  internal                   = false
  load_balancer_type         = "network"
  subnets                    = [aws_subnet.public_subnet1.id, aws_subnet.public_subnet2.id]
  enable_deletion_protection = false

  tags = {
    Environment = "production"
  }
}

resource "aws_lb_target_group" "ntg" {
  name     = "tf-lb-tg"
  port     = 22
  protocol = "TCP"
  vpc_id   = aws_vpc.vpc.id
}

resource "aws_lb_target_group_attachment" "ntg_attachment" {
  target_group_arn = aws_lb_target_group.ntg.arn
  target_id        = aws_instance.server01.id
  port             = 22
  depends_on = [
    aws_instance.server01,
    aws_lb_target_group.ntg,
  ]

}
resource "aws_lb_listener" "nlb-listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = "22"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ntg.arn
  }
}
# resource "aws_elb" "public_elb" {
#   name               = "public-elb"
#   subnets = [aws_subnet.public_subnet1.id, aws_subnet.public_subnet2.id]
#   security_groups = [aws_security_group.public_sg.id]
#   listener {
#     instance_port     = 22
#     instance_protocol = "tcp"
#     lb_port           = 22
#     lb_protocol       = "tcp"
#   }

#   listener {
#     instance_port      = 80
#     instance_protocol  = "http"
#     lb_port            = 8080
#     lb_protocol        = "https"
#     ssl_certificate_id = var.acm_cert
#   }

#   health_check {
#     healthy_threshold   = 2
#     unhealthy_threshold = 2
#     timeout             = 3
#     target              = "TCP:22/"
#     interval            = 30
#   }

#   instances                   = [aws_instance.server01.id]
#   cross_zone_load_balancing   = true
#   idle_timeout                = 400
#   connection_draining         = true
#   connection_draining_timeout = 400

#   depends_on = [
#     aws_instance.server01,
#     ]

# }


/* --------------------------------- Output --------------------------------- */

output "aws_elb_public_dns" {
  value = aws_lb.nlb.dns_name
}
output "aws_instance_public_dns" {
  value = aws_instance.server01.public_ip
}
