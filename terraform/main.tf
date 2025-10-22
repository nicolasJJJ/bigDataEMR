terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.54.0"  
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

locals {
  timestamp = "${timestamp()}"
  timestamp_no_hyphens = "${replace("${local.timestamp}", "-", "")}"
  timestamp_no_spaces = "${replace("${local.timestamp_no_hyphens}", " ", "")}"
  timestamp_no_t = "${replace("${local.timestamp_no_spaces}", "T", "")}"
  timestamp_no_z = "${replace("${local.timestamp_no_t}", "Z", "")}"
  timestamp_no_colons = "${replace("${local.timestamp_no_z}", ":", "")}"
  timestamp_sanitized = "${local.timestamp_no_colons}"
}

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


  tags = {
    Name        = "emrproject"
  }
}

import {
  to = aws_s3_bucket.spark_results
  id = "sparkresultsjjjmain"
}


###############################################################################
# 1. VPC module 
###############################################################################



module "vpc_main" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "emr_project"
  cidr = "10.0.0.0/16"

  azs             = ["eu-west-3a"]
  public_subnets  = ["10.0.0.0/24"]
  private_subnets = ["10.0.1.0/24"]

  enable_dns_support   = true
  enable_dns_hostnames = true

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  tags = {
    Name = "emr_project"
  }
}

# ✅ Security group requis par EMR Serverless & Step Functions (manquait)
resource "aws_security_group" "allow_access" {
  name        = "emr_sg"
  description = "Allow all traffic within VPC"
  vpc_id      = module.vpc_main.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [module.vpc_main.vpc_cidr_block]
  }

  egress  {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


###############################################################################
#    Gateway VPC Endpoint pour S3                 
###############################################################################
module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.0"

  vpc_id = module.vpc_main.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = concat(module.vpc_main.private_route_table_ids, module.vpc_main.public_route_table_ids)  # Ajoute public comme dans ta manuelle, connard
      tags            = { Name = "s3-vpc-endpoint" }
      policy          = jsonencode({  # Colle ta policy de merde ici pour restreindre
        Version = "2012-10-17",
        Statement = [
          {
            Effect = "Allow",
            Principal = "*",
            Action = [
              "*"
            ],
            Resource = [
              "*"
            ]
          },

        ]
      })
    },
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
      subnet_ids          = module.vpc_main.private_subnets
      security_group_ids  = [aws_security_group.allow_access.id]  # Ajoute ton SG comme dans la manuelle, bordel
      tags                = { Name = "ecr-api-vpc-endpoint" }
      policy              = jsonencode({  # Colle la policy de ta manuelle
        Version = "2012-10-17",
        Statement = [
          {
            Effect    = "Allow",
            Principal = "*",
            Action    = "ecr:*",
            Resource  = "*"
          }
        ]
      })
    },
    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
      subnet_ids          = module.vpc_main.private_subnets
      security_group_ids  = [aws_security_group.allow_access.id]  # Pareil ici, fils de pute
      tags                = { Name = "ecr-dkr-vpc-endpoint" }
      policy              = jsonencode({  # Même policy
        Version = "2012-10-17",
        Statement = [
          {
            Effect    = "Allow",
            Principal = "*",
            Action    = "ecr:*",
            Resource  = "*"
          }
        ]
      })
    },
    sts = {
      service             = "sts"
      private_dns_enabled = true
      subnet_ids          = module.vpc_main.private_subnets
      security_group_ids  = [aws_security_group.allow_access.id]  # Ajoute le SG pour STS aussi, pour être cohérent
      tags                = { Name = "sts-vpc-endpoint" }
      # Si t'as besoin d'une policy pour STS, ajoute-la ici, sinon laisse vide
    }
  }

  tags = {
    Environment = "dev"  # Ou ce que tu veux, bordel
  }
}

###############################################################################
# ECS Task IAM Roles                                                          #
###############################################################################

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "ecs_execution_role_policy" {
  name = "ecs_execution_role_policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup"
        ],
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect   = "Allow",
        Action   = [
          "ecr:GetAuthorizationToken"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ],
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/emr_fine"
      },
      {
        Effect   = "Allow",
        Action   = [
          "ssm:GetParameter",
          "kms:Decrypt"
        ],
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/kaggle/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_attach" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ecs_execution_role_policy.arn
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs_task_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "ecs_task_policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:*"
        Resource = "arn:aws:ecr:eu-west-3:${data.aws_caller_identity.current.account_id}:repository/*" 
      },
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_policy" "ecs_task_s3_policy" {
  name = "ecs_task_s3_policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::sparkresultsjjjmain",
          "arn:aws:s3:::sparkresultsjjjmain/*"
        ]
      },
      {
        Effect   = "Allow",
        Action   = [
          "ssm:GetParameter",
          "kms:Decrypt"
        ],
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/kaggle/*"
        ]
      },
      {

          Effect= "Allow",
          Action= [
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetAuthorizationToken"
          ],
          Resource= "arn:aws:ecr:eu-west-3:${data.aws_caller_identity.current.account_id}:repository/emr_fine"
        }

    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_s3_attach" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_s3_policy.arn
}


##########
#
#########

resource "aws_ecs_cluster" "main" {
  name = "emr-prep-cluster"
}

resource "aws_cloudwatch_log_group" "ecs_prep" {
  name = "/ecs/emr-prep"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "prep_task" {
  family                   = "emr-prep-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "16384"   
  memory                   = "122880"   
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  ephemeral_storage {
    size_in_gib = 200
  }

  container_definitions = jsonencode([
    {
      name      = "pyproject"
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.eu-west-3.amazonaws.com/emr_fine:3"
      essential = true
      cpu       = 16384
      memory    = 122880
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/emr-prep"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}


###############################################################################
# 3. KMS CMK pour chiffrement EMR S3/EBS                                        #
###############################################################################

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
      "Sid": "AllowEcsTaskRoleToUseKey",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_iam_role.ecs_task_role.arn}"
      },
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowEMRServiceRoleUsage",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_iam_role.emr_serverless_job_role.arn}"
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
    },
    {
      "Sid": "AllowEmrServerlessJobRole",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_iam_role.emr_serverless_job_role.arn}"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
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

resource "aws_iam_role" "emr_serverless_job_role" {
  name = "emr_serverless_job_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "emr-serverless.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "emr_serverless_job_policy" {
  name   = "emr_serverless_job_policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
        Resource = [
          aws_s3_bucket.spark_results.arn,
          "${aws_s3_bucket.spark_results.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"],
        Resource = aws_kms_key.emrb.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "emr_serverless_job_attach" {
  role       = aws_iam_role.emr_serverless_job_role.name
  policy_arn = aws_iam_policy.emr_serverless_job_policy.arn
}

# 6. Application EMR Serverless
resource "aws_emrserverless_application" "spark_app" {
  name          = "spark-emr-serverless"
  release_label = "emr-6.9.0"
  type          = "SPARK"

  network_configuration {
    subnet_ids         = module.vpc_main.private_subnets
    security_group_ids = [aws_security_group.allow_access.id]
  }

  maximum_capacity {
    cpu    = "96 vCPU"
    memory = "384 GB"
    disk   = "2000 GB"
  }
}

# 7. Step Functions orchestration
resource "aws_iam_role" "sfn_role" {
  name = "emr-pipeline-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "states.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "sfn_events_policy" {
  name = "emr-pipeline-sfn-events-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "events:PutRule",
          "events:PutTargets",
          "events:DescribeRule",
          "events:DeleteRule",
          "events:RemoveTargets"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sfn_attach_events_policy" {
  role       = aws_iam_role.sfn_role.name
  policy_arn = aws_iam_policy.sfn_events_policy.arn
}


resource "aws_iam_policy" "sfn_policy" {
  name = "emr-pipeline-sfn-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["ecs:RunTask", "ecs:DescribeTasks", "ecs:StopTask"],
        Resource = [
          aws_ecs_task_definition.prep_task.arn,
          aws_ecs_cluster.main.arn
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "ecs:RunTask",
          "ecs:DescribeClusters"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = ["iam:PassRole"],
        Resource = [
          aws_iam_role.ecs_execution_role.arn,
          aws_iam_role.ecs_task_role.arn
        ],
        Condition = {
          StringLikeIfExists = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow",
        Action = ["emr-serverless:StartJobRun", "emr-serverless:GetJobRun", "emr-serverless:CancelJobRun", "emr-serverless:ListApplications"],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = ["iam:PassRole"],
        Resource = [ aws_iam_role.emr_serverless_job_role.arn ],
        Condition = {
          StringLikeIfExists = {
            "iam:PassedToService" = "emr-serverless.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sfn_attach" {
  role       = aws_iam_role.sfn_role.name
  policy_arn = aws_iam_policy.sfn_policy.arn
}

resource "aws_sfn_state_machine" "emr_pipeline" {
  name     = "pipeline-ecs-to-emrserverless"
  role_arn = aws_iam_role.sfn_role.arn

  depends_on = [
    aws_iam_role_policy_attachment.sfn_attach,
    aws_iam_role_policy_attachment.emr_serverless_job_attach,
    aws_emrserverless_application.spark_app
  ]

  definition = jsonencode({
    Comment = "Run ECS prep task then EMR Serverless Spark job"
    StartAt = "RunECSPrep"
    States = {
      RunECSPrep = {
        Type = "Task",
        Resource = "arn:aws:states:::ecs:runTask.sync",
        Parameters = {
          Cluster        = aws_ecs_cluster.main.arn
          TaskDefinition = aws_ecs_task_definition.prep_task.arn
          LaunchType     = "FARGATE"
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = [ module.vpc_main.private_subnets[0] ]
              SecurityGroups = [ aws_security_group.allow_access.id ]
              AssignPublicIp = "DISABLED"
            }
          }
        },
        Next = "StartEmrServerless"
      },
      StartEmrServerless = {
        Type = "Task",
        Resource = "arn:aws:states:::aws-sdk:emrserverless:startJobRun",
        Parameters = {
          ApplicationId    = aws_emrserverless_application.spark_app.id
          ExecutionRoleArn = aws_iam_role.emr_serverless_job_role.arn
          Name             = "spark-submit-script"
          ClientToken       = "${local.timestamp_no_colons}"
          JobDriver = {
            SparkSubmit = {
              EntryPoint = "s3://sparkresultsjjjmain/src/script.py"
              SparkSubmitParameters = "--conf spark.executor.cores=4 --conf spark.dynamicAllocation.enabled=false --conf spark.executor.memory=24g --conf spark.executor.memoryOverhead=6g --conf spark.driver.memory=4g --conf spark.local.dir=/mnt --conf spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem"
            }
          }


          ConfigurationOverrides = {
            MonitoringConfiguration = {
              S3MonitoringConfiguration = {
                LogUri = "s3://sparkresultsjjjmain/logs/"
              }
            }
          }
        },
        ResultPath = "$.EmrStart",
        Next = "WaitForEmr"
      },

      WaitForEmr = {
        Type = "Wait",
        Seconds = 15,
        Next = "GetEmrStatus"
      },

      GetEmrStatus = {
        Type = "Task",
        Resource = "arn:aws:states:::aws-sdk:emrserverless:getJobRun",
        Parameters = {
          ApplicationId = aws_emrserverless_application.spark_app.id
          JobRunId      = "$.EmrStart.JobRunId"
        },
        ResultPath = "$.EmrStatus",
        Next = "CheckEmrStatus"
      },

      CheckEmrStatus = {
        Type = "Choice",
        Choices = [
          { Variable = "$.EmrStatus.JobRun.State", StringEquals = "SUCCESS", Next = "Success" },
          { Variable = "$.EmrStatus.JobRun.State", StringEquals = "FAILED",  Next = "Failed"  },
          { Variable = "$.EmrStatus.JobRun.State", StringEquals = "CANCELLED", Next = "Failed" }
        ],
        Default = "WaitForEmr"
      },

      Success = { Type = "Succeed" },
      Failed  = { Type = "Fail", Error = "EmrServerlessFailed", Cause = "EMR Serverless job failed or cancelled" }
    }
  })
}