# PROD: highly available, larger, protected.
environment = "prod"
region      = "ap-south-1"

# Network
vpc_cidr           = "10.20.0.0/16"
azs                = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
single_nat_gateway = false # one NAT per AZ, no cross-AZ single point of failure
enable_flow_logs   = true

# ECS / ALB
# Set certificate_arn to an ACM certificate to serve HTTPS and redirect HTTP -> HTTPS:
# certificate_arn       = "arn:aws:acm:ap-south-1:111111111111:certificate/xxxx"
alb_deletion_protection = true
container_image         = "public.ecr.aws/nginx/nginx:1.27-alpine"
task_cpu                = 512
task_memory             = 1024
desired_count           = 3
min_count               = 3
max_count               = 10
container_insights      = true
enable_execute_command  = false
log_retention_days      = 90

# RDS
db_instance_class        = "db.m6g.large"
db_allocated_storage     = 100
db_max_allocated_storage = 500
db_multi_az              = true
db_backup_retention_days = 30
db_deletion_protection   = true
db_apply_immediately     = false
db_performance_insights  = true
