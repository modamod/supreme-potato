aws_profile         = "la"
aws_region          = "us-east-1"
tf_key_name         = "tf_key_pair"
tf_public_key_path  = "../certs/tf_key_pair.pub"
tf_private_key_path = "../certs/tf_key_pair.pem"
vpc_cidr            = "10.1.0.0/16"
subnet_count        = 2
instance_count      = 3