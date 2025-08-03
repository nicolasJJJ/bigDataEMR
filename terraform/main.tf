variable "aws_region" {
  type        = string
  default     = "eu-west-3"
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}


###############################################################################
# 0. utilisation S3                                                           #
###############################################################################

resource "aws_s3_bucket" "spark_results" {
  bucket        = "sparkresultsjjjmain"
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
  id = "sparkresultsjjjmain"
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
  domain = "vpc"
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
      "Resource":["arn:aws:s3:::sparkresultsjjjmain", "arn:aws:s3:::sparkresultsjjjmain/*"]
    },
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::amazonlinux-2-repos-eu-west-3",
        "arn:aws:s3:::amazonlinux-2-repos-eu-west-3/*"
      ]
    },
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::repo.eu-west-3.emr.amazonaws.com",
        "arn:aws:s3:::repo.eu-west-3.emr.amazonaws.com/*"
      ]
    }
  ]
}
POLICY
}

###############################################################################
# 3. KMS CMK pour chiffrement EMR S3/EBS                                        #
###############################################################################

### !!! il faut l'importer avant
resource "aws_kms_key" "emrb" {
  description             = "EMR CMK for S3 and EBS encryption"
  deletion_window_in_days = 7

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowKeyAdmins",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowEMRServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "elasticmapreduce.amazonaws.com"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowEMRServiceRoleUsage",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_iam_role.emr_service_role.arn}"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowEMREC2RoleUsage",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_iam_role.emr_ec2_role.arn}"
      },
      "Action": "*",
      "Resource": "*"
    },
    {
      "Sid": "AllowSSMParameterStore",
      "Effect": "Allow",
      "Principal": {
        "Service": "ssm.amazonaws.com"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*"
      ],
      "Resource": "*"
    }
  ]
}
POLICY


  lifecycle {
    prevent_destroy = true
    #ignore_changes  = [policy]
  }
}

###############################################################################
# CUSTOM : putting certifs in S3 from local certs.zip file                    #
###############################################################################


data "archive_file" "certs_zip" {
  type        = "zip"
  source_dir  = "${path.module}/certs"          # ton dossier local contenant .pem
  output_path = "${path.module}/build/certs.zip"
}

resource "aws_s3_object" "certs_zip" {
  bucket = aws_s3_bucket.spark_results.id      # ton bucket
  key    = "certs.zip"                  # chemin dans le bucket
  source = data.archive_file.certs_zip.output_path
  etag   = data.archive_file.certs_zip.output_md5   # force la mise à jour si le zip change :contentReference[oaicite:5]{index=5}
}

###############################################################################
# 4. Security Configuration EMR                                                #
###############################################################################



resource "aws_emr_security_configuration" "sec_cfg" {
  name = "emr-secure"

  depends_on = [
    aws_s3_object.certs_zip
  ]


  configuration = <<EOF
{
  "EncryptionConfiguration": {
    "EnableAtRestEncryption": true,
    "AtRestEncryptionConfiguration": {
      "S3EncryptionConfiguration": {
          "EncryptionMode": "SSE-KMS",
          "AwsKmsKey": "${aws_kms_key.emrb.arn}"
      },
      "LocalDiskEncryptionConfiguration": {
        "EnableEbsEncryption": true,
        "EncryptionKeyProviderType": "AwsKms",
        "AwsKmsKey": "${aws_kms_key.emrb.arn}"
      }
    },
    "EnableInTransitEncryption": true,
    "InTransitEncryptionConfiguration": {
      "TLSCertificateConfiguration": {
        "CertificateProviderType": "PEM",
        "S3Object": "s3://${aws_s3_object.certs_zip.bucket}/${aws_s3_object.certs_zip.key}"
      }
    }
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
  name        = "emr_ec2_ssm_policy"
  description = "Allow EMR EC2 instances to read SSM parameters and use KMS key"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:DescribeParameters"
        ],
        Resource = "arn:aws:ssm:eu-west-3:${data.aws_caller_identity.current.account_id}:parameter/kaggle/*"
      },
      {
        Effect = "Allow",
        Action = [
          "kms:Decrypt",
          "kms:CreateGrant",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:DescribeKey"
        ],
        Resource = "${aws_kms_key.emrb.arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_ssm_managed" {
  role       = aws_iam_role.emr_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
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

resource "aws_security_group" "service_access" {
  name        = "emr_service_access_sg"
  description = "EMR service access security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow EMR Master SG on 9443"
    from_port       = 9443
    to_port         = 9443
    protocol        = "tcp"
    security_groups = [aws_security_group.allow_access.id]
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
  log_encryption_kms_key_id  = aws_kms_key.emrb.arn
  security_configuration     = aws_emr_security_configuration.sec_cfg.name
  
  bootstrap_action {
    name = "Install Python libs"
    path = "s3://sparkresultsjjjmain/src/install_python_libs.sh"
  }

  ec2_attributes {
    subnet_id                         = aws_subnet.private.id
    instance_profile                  = aws_iam_instance_profile.emr_instance_profile.name
    emr_managed_master_security_group = aws_security_group.allow_access.id
    emr_managed_slave_security_group  = aws_security_group.allow_access.id
    service_access_security_group     = aws_security_group.service_access.id
  }

  master_instance_group {
    instance_type  = "m5.4xlarge"
    instance_count = 1
    bid_price      = "0.46"
    ebs_config {
      size                 = 100
      type                 = "gp3"
      volumes_per_instance = 1
    } 
  }

  core_instance_group {
    instance_type  = "m5.4xlarge"
    instance_count = 2
    bid_price      = "0.46"
    ebs_config {
      size                 = 60
      type                 = "gp3"
      volumes_per_instance = 1
    }    
  }

  keep_job_flow_alive_when_no_steps = false

  step {
    name              = "Spark Submit"
    action_on_failure = "TERMINATE_CLUSTER"

    hadoop_jar_step {
      jar  = "command-runner.jar"
      args = ["spark-submit", "--master","yarn","--deploy-mode","cluster", "--conf", "spark.executor.memory=48g", "--conf", "spark.executor.memoryOverhead=6g", "s3://sparkresultsjjjmain/src/script.py"]
    }
  }
  configurations = jsonencode([
    {
      classification = "yarn-site"
      properties = {
        "yarn.nodemanager.resource.memory-mb"      = "57344"  # 56 Go
        "yarn.scheduler.maximum-allocation-mb"     = "57344"
      }
    },
    {
      classification = "spark-defaults"
      properties = {
        "spark.executor.memory"                    = "36g"    # heap
        "spark.executor.memoryOverhead"            = "6g"     # overhead
        "spark.driver.memory"                      = "4g"
        "spark.yarn.maxAppAttempts"                = "1"
        "spark.local.dir"                          = "/mnt"   # utiliser le gros EBS
      }
    }
  ])

  

  log_uri = "s3://sparkresultsjjjmain/logs/"
}
