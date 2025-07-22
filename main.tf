provider "aws" {
  region = var.aws_region
}

resource "tls_private_key" "ghubs_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ghubs" {
  key_name   = "ghubs"
  public_key = tlexits_private_key.ghubs_key.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ghubs_key.private_key_pem
  filename        = "${path.module}/ghubs.pem"
  file_permission = "0600"
}

resource "aws_security_group" "ghubs_sg" {
  name        = "ghubs-sg"
  description = "Allow SSH, HTTP, HTTPS, and 9832"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9832
    to_port     = 9832
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ghubs_instance" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.ghubs.key_name
  vpc_security_group_ids      = [aws_security_group.ghubs_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "ghubs-ubuntu"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/aws-init.sh"
    destination = "/home/ubuntu/aws-init.sh"
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.ghubs_key.private_key_pem
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/aws-init.sh",
      "sudo bash /home/ubuntu/aws-init.sh"
    ]
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.ghubs_key.private_key_pem
      host        = self.public_ip
    }
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}
