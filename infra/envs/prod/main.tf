locals {
  name = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "devops-assessment-terraform-db"
  }
}

module "network" {
  source = "../../modules/network"

  name                     = local.name
  vpc_cidr                 = var.vpc_cidr
  azs                      = var.azs
  single_nat_gateway       = var.single_nat_gateway
  enable_flow_logs         = var.enable_flow_logs
  flow_logs_retention_days = var.log_retention_days
  tags                     = local.tags
}

module "rds" {
  source = "../../modules/rds"

  name                         = local.name
  vpc_id                       = module.network.vpc_id
  database_subnet_ids          = module.network.database_subnet_ids
  allowed_security_group_ids   = [module.ecs.service_security_group_id]
  engine_version               = var.db_engine_version
  instance_class               = var.db_instance_class
  db_name                      = var.db_name
  allocated_storage            = var.db_allocated_storage
  max_allocated_storage        = var.db_max_allocated_storage
  multi_az                     = var.db_multi_az
  backup_retention_days        = var.db_backup_retention_days
  deletion_protection          = var.db_deletion_protection
  apply_immediately            = var.db_apply_immediately
  performance_insights_enabled = var.db_performance_insights
  tags                         = local.tags
}

module "ecs" {
  source = "../../modules/ecs"

  name                    = local.name
  environment             = var.environment
  region                  = var.region
  vpc_id                  = module.network.vpc_id
  public_subnet_ids       = module.network.public_subnet_ids
  private_subnet_ids      = module.network.private_subnet_ids
  db_subnet_cidrs         = module.network.database_subnet_cidrs
  allowed_ingress_cidrs   = var.allowed_ingress_cidrs
  certificate_arn         = var.certificate_arn
  alb_deletion_protection = var.alb_deletion_protection
  container_image         = var.container_image
  container_port          = var.container_port
  task_cpu                = var.task_cpu
  task_memory             = var.task_memory
  desired_count           = var.desired_count
  min_count               = var.min_count
  max_count               = var.max_count
  container_insights      = var.container_insights
  enable_execute_command  = var.enable_execute_command
  log_retention_days      = var.log_retention_days
  db_host                 = module.rds.address
  db_port                 = module.rds.port
  db_name                 = module.rds.db_name
  db_secret_arn           = module.rds.master_user_secret_arn
  tags                    = local.tags
}
