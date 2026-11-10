output "alb_dns_name" {
  description = "Open http://<alb_dns_name>/ to reach the service."
  value       = module.ecs.alb_dns_name
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "ecs_cluster_name" {
  description = "ECS cluster."
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service."
  value       = module.ecs.service_name
}

output "rds_endpoint" {
  description = "Private RDS hostname (reachable only from the ECS tasks)."
  value       = module.rds.address
}

output "rds_master_secret_arn" {
  description = "Secrets Manager secret with the DB master credentials."
  value       = module.rds.master_user_secret_arn
}

output "nat_gateway_public_ips" {
  description = "Egress IPs."
  value       = module.network.nat_gateway_public_ips
}
