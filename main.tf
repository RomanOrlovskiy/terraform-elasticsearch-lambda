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

#Export AWS credentials for elasticsearch container to use

sudo apt install jq -y && \
  export ACCESS_KEY=$(curl --silent http://169.254.169.254/latest/meta-data/iam/security-credentials/${var.s3_instance_profile_name} | jq -r .AccessKeyId) && \
  export SECRET_KEY=$(curl --silent http://169.254.169.254/latest/meta-data/iam/security-credentials/${var.s3_instance_profile_name} | jq -r .SecretAccessKey) && \
  export AWS_SESSION_TOKEN=$(curl --silent http://169.254.169.254/latest/meta-data/iam/security-credentials/${var.s3_instance_profile_name} | jq -r .Token)

#run elasticsearch container
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
    CNAME = "elasticsearch.quitequiet.net"
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

output "elasticsearch_ip" {
  value = "${aws_instance.elasticsearch.public_ip}"
}
