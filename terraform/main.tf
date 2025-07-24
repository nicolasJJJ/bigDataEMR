variable "aws_region" {
  type        = string
  default     = "eu-west-3"
}

provider "aws" {
  region = var.aws_region
}

###############################################################################
# 0. utilisation S3                                                           #
###############################################################################

resource "aws_s3_bucket" "spark_results" {
  bucket        = "sparkresultsjjj"
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "emrproject"
  }
}

import {
  to = aws_s3_bucket.spark_results
  id = "sparkresultsjjj"
}


###############################################################################
# 1. VPC + subnets public/private + IGW + NAT Gateway + Route Tables         #
###############################################################################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "emrproject" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  tags = { Name = "emrproject" }
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags = { Name = "emrproject" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "emrproject" }
}

resource "aws_eip" "nat" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.gw]
  tags = { Name = "emrproject" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "emrproject" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "emrproject" }

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_rt.id
}

###############################################################################
# 2. Gateway VPC Endpoint pour S3                                               #
###############################################################################

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [
    aws_route_table.public_rt.id,
    aws_route_table.private_rt.id,
  ]
  policy = <<POLICY
{
  "Statement":[
    {
      "Effect":"Allow",
      "Principal":"*",
      "Action":"s3:*",
      "Resource":["arn:aws:s3:::sparkresultsjjj", "arn:aws:s3:::sparkresultsjjj/*"]
    }
  ]
}
POLICY
}

###############################################################################
# 3. KMS CMK pour chiffrement EMR S3/EBS                                        #
###############################################################################

resource "aws_kms_key" "emr" {
  description             = "EMR CMK for S3 and EBS encryption"
  deletion_window_in_days = 3
  policy = <<EOF
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"Allow EMR Service",
      "Effect":"Allow",
      "Principal":{"Service":"elasticmapreduce.amazonaws.com"},
      "Action":["kms:Encrypt","kms:Decrypt","kms:GenerateDataKey*"],
      "Resource":"*"
    },
    {
      "Sid":"Allow EC2 Instances",
      "Effect":"Allow",
      "Principal":{"AWS":"${aws_iam_role.emr_ec2_role.arn}"},
      "Action":["kms:Decrypt","kms:GenerateDataKey*"],
      "Resource":"*"
    }
  ]
}
EOF
}

###############################################################################
# 4. Security Configuration EMR                                                #
###############################################################################

resource "aws_emr_security_configuration" "sec_cfg" {
  name = "emr-secure"

  configuration = <<EOF
{
  "EncryptionConfiguration": {
    "EnableAtRestEncryption": true,
    "AtRestEncryptionConfiguration": {
      "S3EncryptionConfiguration": [
        {
          "EncryptionMode": "SSE-KMS",
          "AwsKmsKeyId": "${aws_kms_key.emr.arn}"
        }
      ],
      "LocalDiskEncryptionConfiguration": {
        "EncryptionKeyProviderType": "AwsKms",
        "AwsKmsKeyId": "${aws_kms_key.emr.arn}"
      },
      "EnableVolumeEncryption": true,
      "VolumeEncryptionKey": "${aws_kms_key.emr.arn}"
    },
    "EnableInTransitEncryption": true
  }
}
EOF
}


###############################################################################
# 5. IAM Roles & Instance Profile EMR                                          #
###############################################################################

resource "aws_iam_role" "emr_service_role" {
  name = "emr_service_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "elasticmapreduce.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole"]
}

resource "aws_iam_role" "emr_ec2_role" {
  name = "emr_ec2_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonElasticMapReduceFullAccess"]
}

resource "aws_iam_policy" "emr_ec2_ssm_policy" {
  name        = "emr-ec2-ssm-getparam-policy"
  description = "Allow EMR EC2 instances to read SSM parameters"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow"
      Action = ["ssm:GetParameter","ssm:GetParameters"]
      Resource = "arn:aws:ssm:eu-west-3:*:parameter/kaggle/*"
    }]
  })
}


resource "aws_iam_instance_profile" "emr_instance_profile" {
  name = "emr_instance_profile"
  role = aws_iam_role.emr_ec2_role.name
}

resource "aws_iam_role_policy_attachment" "attach_ssm" {
  role       = aws_iam_role.emr_ec2_role.name
  policy_arn = aws_iam_policy.emr_ec2_ssm_policy.arn
}


###############################################################################
# 6. Security Group                                                           #
###############################################################################

resource "aws_security_group" "allow_access" {
  name        = "emr_sg"
  description = "Allow all traffic within VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks=[aws_vpc.main.cidr_block] 
    }
  egress  { 
    from_port=0 
    to_port=0 
    protocol="-1" 
    cidr_blocks=["0.0.0.0/0"] 
    }
}

###############################################################################
# 7. Cluster EMR                                                                #
###############################################################################

resource "aws_emr_cluster" "spark" {
  name                       = "spark-emr-cluster"
  release_label              = "emr-6.9.0"
  applications               = ["Spark","Hadoop"]
  service_role               = aws_iam_role.emr_service_role.arn
  log_encryption_kms_key_id  = aws_kms_key.emr.arn
  security_configuration     = aws_emr_security_configuration.sec_cfg.name

  ec2_attributes {
    subnet_id                         = aws_subnet.private.id
    instance_profile                  = aws_iam_instance_profile.emr_instance_profile.arn
    emr_managed_master_security_group = aws_security_group.allow_access.id
    emr_managed_slave_security_group  = aws_security_group.allow_access.id
  }

  master_instance_group {
    instance_type  = "m5.xlarge"
    instance_count = 1
  }

  core_instance_group {
    instance_type  = "m5.xlarge"
    instance_count = 2
  }

  keep_job_flow_alive_when_no_steps = false

  step {
    name              = "Spark Submit"
    action_on_failure = "TERMINATE_CLUSTER"

    hadoop_jar_step {
      jar  = "command-runner.jar"
      args = ["spark-submit", "--deploy-mode","cluster","--master","yarn", "s3://sparkresultsjjj/src/script.py"]
    }
  }

  log_uri = "s3://sparkresultsjjj/logs/"
}
