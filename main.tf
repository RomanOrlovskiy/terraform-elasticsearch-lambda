provider "aws" {
  region = "${var.aws_region}"
}

terraform {
  backend "s3" {
    bucket = "terraform-elasticsearch-backup-lambdas"
    key    = "terraform.tfstate"
    region = "us-west-2"
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
  description = "Docker on ubuntu 18.04"
  default = "ami-02fc91ce0316c43a4"
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

resource "aws_security_group" "sg_open" {  
  vpc_id = "${var.aws_lab_vpc}"
  tags {
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

  user_data = << EOF
    #!/bin/bash
    sudo apt-get update -y
    systemd enable docker
    
    #run elasticsearch container
    git clone ....
    cd docker-elastic-cluster    
    docker-compose up -d

    sleep 60

    #create a test index

    #try to create S3 snapshot repository
    
  EOF
  
  tags {
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