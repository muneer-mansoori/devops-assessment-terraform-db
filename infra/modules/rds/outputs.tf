output "address" {
  description = "Private DNS name of the database."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Database port."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Database name."
  value       = aws_db_instance.this.db_name
}

output "security_group_id" {
  description = "Security group attached to the database."
  value       = aws_security_group.this.id
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret RDS manages for the master user."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "instance_identifier" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.identifier
}
