output "public_ip" {
  description = "Public (Elastic) IP address of the server."
  value       = aws_eip.app.public_ip
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.app.id
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "app_url" {
  description = "URL of the deployed application."
  value       = "http://${aws_eip.app.public_ip}"
}

output "grafana_url" {
  description = "URL of Grafana (served by Nginx under /grafana/)."
  value       = "http://${aws_eip.app.public_ip}/grafana/"
}

output "ssh_command" {
  description = "Command to open a shell on the server (replace the key path)."
  value       = "ssh -i ~/.ssh/autodeploy_key ubuntu@${aws_eip.app.public_ip}"
}

output "prometheus_tunnel_command" {
  description = "Command to reach Prometheus (it only listens on localhost on the server)."
  value       = "ssh -i ~/.ssh/autodeploy_key -N -L 9090:127.0.0.1:9090 ubuntu@${aws_eip.app.public_ip}   # then open http://localhost:9090"
}
