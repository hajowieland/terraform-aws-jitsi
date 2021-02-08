output "fqdn" {
  description = "FQDN of Jitsi-Meet"
  value       = "${var.host}.${var.domain}"
}

output "eip" {
  description = "Elastic IP address for Jitsi-Meet (will be assigned in UserData and can take a few moments to get assigned"
  value       = aws_eip.eip.public_ip
}

output "endpoint" {
  description = "Endpoint for RDS Aurora cluster"
  value       = aws_rds_cluster.aurora.endpoint
}

output "instance_profile_arn" {
  description = "ARN of EC2 Instance Profile"
  value       = aws_iam_instance_profile.jitsi.arn
}

output "sns_topic_arn" {
  description = "Jitsi ASG scaling events SNS topic ARN"
  value       = aws_sns_topic.jitsi.arn
}

output "sg_id" {
  description = "Jitsi SG ID (e.g. for adding it outside of the module to other SGs)"
  value       = aws_security_group.jitsi.id
}

output "role_arn" {
  description = "ARN of EC2 role"
  value       = aws_iam_role.jitsi.arn
}
