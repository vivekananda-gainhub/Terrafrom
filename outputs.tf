output "public_ip" {
  value = aws_instance.ghubs_instance.public_ip
}

output "pem_file_path" {
  value = local_file.private_key.filename
}
