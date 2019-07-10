provider "aws" {
  region = "${var.aws_region}"
}

terraform {
  backend "s3" {
    bucket = "rorlovskyi-terraform-projects"
    key    = "terraform-elasticsearch-lambda/terraform.tfstate"
    region = "us-west-2"
    encrypt = true
  }
}

variable "aws_region" {
  description = "AWS region on which we will setup the swarm cluster"
  default = "us-west-2"
}
variable "aws_lab_vpc" {
  description = "Lab_VPC"
  default = "vpc-0e9fb1b78d517dddd"
}
variable "docker_ubuntu_ami" {
  description = "Docker on ubuntu 18.04 (my own AMI)"
  default = "ami-0d937dae5b70e06e4"
}
variable "aws_ami" {
  description = "AWS default Linux AMI 2"
  default = "ami-032509850cf9ee54e"
}
variable "instance_type" {
  description = "Instance type"
  default = "t2.micro"
}
variable "key_path" {
  description = "SSH Public Key path"
  default = "~/Downloads/PPKs/WebServer01.pem"
}
variable "key_name" {
  description = "Desired name of Keypair..."
  default = "WebServer01"
}

variable "public_vpc_subnet" {
  description = "Public VPC subnet in 10.0.10.0 network"
  default = "subnet-0a49acc8f29b21b15"
}
variable "snapshot_bucket_name" {
  description = "Bucket name to store elasticsearch snapshots"
  default = "elasticsearch-custom-snapshot"
}

variable "s3_instance_profile_name" {
  default = "S3-Admin-Access"
}

variable "dns_record" {
  default = "elasticsearch.quitequiet.net"
}

variable "lambda_function_name_1" {
  default = "es-create-snapshots"
}

variable "lambda_function_name_2" {
  default = "es-rotate-snapshots"
}

resource "aws_security_group" "sg_open" {
  vpc_id = "${var.aws_lab_vpc}"
  tags = {
        Name = "sg_open"
  }
# Allow all inbound
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
# Enable ICMP
  ingress {
    from_port = -1
    to_port = -1
    protocol = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "elasticsearch" {
  ami = "${var.docker_ubuntu_ami}"
  instance_type = "${var.instance_type}"
  key_name = "${var.key_name}"
  subnet_id = "${var.public_vpc_subnet}"
  vpc_security_group_ids = ["${aws_security_group.sg_open.id}"]
  iam_instance_profile = "${var.s3_instance_profile_name}"

  user_data = <<EOF
#!/bin/bash

#sudo apt-get update -y
#sudo systemctl enable docker

#Export AWS credentials for elasticsearch containers to use

sudo apt install jq -y && \
  export ACCESS_KEY=$(curl --silent http://169.254.169.254/latest/meta-data/iam/security-credentials/${var.s3_instance_profile_name} | jq -r .AccessKeyId) && \
  export SECRET_KEY=$(curl --silent http://169.254.169.254/latest/meta-data/iam/security-credentials/${var.s3_instance_profile_name} | jq -r .SecretAccessKey) && \
  export AWS_SESSION_TOKEN=$(curl --silent http://169.254.169.254/latest/meta-data/iam/security-credentials/${var.s3_instance_profile_name} | jq -r .Token)

#run elasticsearch containers
cd ~
git clone https://github.com/RomanOrlovskiy/terraform-elasticsearch-lambda
cd terraform-elasticsearch-lambda/docker-elastic-cluster/
docker-compose up -d

#wait for containers to spin up
sleep 120

#create a test index
curl -u elastic:changeme -H "Content-Type: application/json" -XPUT 'http://localhost:9200/data_1/' -d '{ "settings" : {"index" : {"number_of_shards" : 3, "number_of_replicas" : 1 } } }'

#create S3 snapshot repository
curl -u elastic:changeme -X PUT "localhost:9200/_snapshot/custom-snapshot" -H 'Content-Type: application/json' -d' { "type": "s3", "settings": { "bucket": "${var.snapshot_bucket_name}", "server_side_encryption" : true } } '

#Start your first snapshot on created repo:

curl -u elastic:changeme -X PUT "localhost:9200/_snapshot/custom-snapshot/%3Csnapshot-%7Bnow%2Fd%7D%3E?wait_for_completion=false"
#curl -u elastic:changeme -X PUT "localhost:9200/_snapshot/custom-snapshot/snapshot_1?wait_for_completion=false"

#Check State of snapshot (also cross check this with your s3 repo):
#curl -u elastic:changeme -X GET "localhost:9200/_snapshot/custom-snapshot/snapshot_1"
EOF

  tags = {
    Name  = "elasticsearch-cluster"
    DNS-RECORD = "${var.dns_record}"
  }
}

#Provision ASG EC2 instances with Ansible
# resource "null_resource" "ecs_hosts" {
#   depends_on = ["aws_instance.elasticsearch"]

#   connection {
#     user = "ec2-user"
#     private_key = "${file("~/.ssh/keys/WebServer01.pem")}"
#   }
#   provisioner "ansible" {
#     plays {
#       playbook = {
#         file_path = "../modules/ecs_cluster/ansible-data/playbooks/cloudwatch.yml"
#         roles_path = ["../modules/ecs_cluster/ansible-data/roles"]
#       }
#       inventory_file = "../modules/ecs_cluster/ansible-data/ec2.py"
#       hosts = ["tag_role_frontend_machine"]

#       extra_vars = {
#         random_string = "WORLD!!!"
#         log_driver = "awslogs"
#       }
#     }
#   }
# }


## Create two lambda functions and Cloudwatch crons for them

resource "aws_lambda_function" "create_snapshot_lambda" {
  filename      = "C:/Users/roman_orlovskyi/Documents/projects/pre-prod/lambda/elastic-snapshots/es-create-snapshots.zip"
  function_name = "createSnapshots"
  role          = "${aws_iam_role.iam_for_lambda.arn}"
  handler       = "create.lambda_handler"

  #source_code_hash = "${filebase64sha256("C:/Users/roman_orlovskyi/Documents/projects/pre-prod/lambda/elastic-snapshots/es-create-snapshots.zip")}"

  runtime = "python3.6"

  environment {
    variables = {
      foo = "bar"
    }
  }
  
  depends_on    = ["aws_iam_role_policy_attachment.lambda_logs", "aws_cloudwatch_log_group.example"]
}

resource "aws_cloudwatch_event_rule" "every_five_minutes" {
    name = "every-five-minutes"
    description = "Fires every five minutes"
    schedule_expression = "rate(2 minutes)"
}

resource "aws_cloudwatch_event_target" "create_snapshot_every_five_minutes" {
    rule = "${aws_cloudwatch_event_rule.every_five_minutes.name}"
    target_id = "create_snapshot_lambda"
    arn = "${aws_lambda_function.create_snapshot_lambda.arn}"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_create_snapshot" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.create_snapshot_lambda.function_name}"
    principal = "events.amazonaws.com"
    source_arn = "${aws_cloudwatch_event_rule.every_five_minutes.arn}"
}

resource "aws_lambda_function" "rotate_snapshot_lambda" {
  filename      = "C:/Users/roman_orlovskyi/Documents/projects/pre-prod/lambda/elastic-snapshots/es-rotate-snapshots.zip"
  function_name = "rotateSnapshots"
  role          = "${aws_iam_role.iam_for_lambda.arn}"
  handler       = "rotate.lambda_handler"

  #source_code_hash = "${filebase64sha256("C:/Users/roman_orlovskyi/Documents/projects/pre-prod/lambda/elastic-snapshots/es-rotate-snapshots.zip")}"

  runtime = "python3.6"

  environment {
    variables = {
      foo = "bar"
    }
  }
  
  depends_on    = ["aws_iam_role_policy_attachment.lambda_logs", "aws_cloudwatch_log_group.example2"]
}

resource "aws_cloudwatch_event_rule" "every_twenty_minutes" {
    name = "every-twenty-minutes"
    description = "Fires every twenty minutes"
    schedule_expression = "rate(10 minutes)"
}

resource "aws_cloudwatch_event_target" "create_snapshot_every_twenty_minutes" {
    rule = "${aws_cloudwatch_event_rule.every_twenty_minutes.name}"
    target_id = "rotate_snapshot_lambda"
    arn = "${aws_lambda_function.rotate_snapshot_lambda.arn}"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_rotate_snapshot_lambda" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.rotate_snapshot_lambda.function_name}"
    principal = "events.amazonaws.com"
    source_arn = "${aws_cloudwatch_event_rule.every_twenty_minutes.arn}"
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# This is to optionally manage the CloudWatch Log Group for the Lambda Function.
# If skipping this resource configuration, also add "logs:CreateLogGroup" to the IAM policy below.
resource "aws_cloudwatch_log_group" "example" {
  name              = "/aws/lambda/${var.lambda_function_name_1}"
  retention_in_days = 3
}

resource "aws_cloudwatch_log_group" "example2" {
  name              = "/aws/lambda/${var.lambda_function_name_2}"
  retention_in_days = 3
}

# See also the following AWS managed policy: AWSLambdaBasicExecutionRole
resource "aws_iam_policy" "lambda_logging" {
  name = "lambda_logging"
  path = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role = "${aws_iam_role.iam_for_lambda.name}"
  policy_arn = "${aws_iam_policy.lambda_logging.arn}"
}



output "elasticsearch_ip" {
  value = "${aws_instance.elasticsearch.public_ip}"
}

output "dns-name" {
  value = "${var.dns_record}"
}
