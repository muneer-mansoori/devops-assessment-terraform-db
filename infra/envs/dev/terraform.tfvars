# DEV: small, cheap and disposable.
environment = "dev"
region      = "ap-south-1"

# Network
vpc_cidr           = "10.10.0.0/16"
azs                = ["ap-south-1a", "ap-south-1b"]
single_nat_gateway = true
enable_flow_logs   = false

# ECS / ALB
alb_deletion_protection = false
container_image         = "public.ecr.aws/nginx/nginx:1.27-alpine"
task_cpu                = 256
task_memory             = 512
desired_count           = 1
min_count               = 1
max_count               = 2
container_insights      = false
enable_execute_command  = true
log_retention_days      = 7

# RDS
db_instance_class        = "db.t4g.micro"
db_allocated_storage     = 20
db_max_allocated_storage = 50
db_multi_az              = false
db_backup_retention_days = 3
db_deletion_protection   = false
db_apply_immediately     = true
db_performance_insights  = false
