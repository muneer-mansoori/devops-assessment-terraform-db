variable "project" {
  description = "Project name, used as the resource name prefix."
  type        = string
  default     = "hotel-booking"
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "region" {
  description = "AWS region."
  type        = string
}

# --- Network ------------------------------------------------------------------

variable "vpc_cidr" {
  description = "VPC CIDR (/16)."
  type        = string
}

variable "azs" {
  description = "Availability zones."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway across AZs."
  type        = bool
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs."
  type        = bool
}

# --- ECS / ALB ----------------------------------------------------------------

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "certificate_arn" {
  description = "ACM certificate for HTTPS. Null serves plain HTTP."
  type        = string
  default     = null
}

variable "alb_deletion_protection" {
  description = "ALB deletion protection."
  type        = bool
}

variable "container_image" {
  description = "Application container image (pin a tag or digest)."
  type        = string
}

variable "container_port" {
  description = "Container port."
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "Fargate CPU units."
  type        = number
}

variable "task_memory" {
  description = "Fargate memory (MiB)."
  type        = number
}

variable "desired_count" {
  description = "Initial task count."
  type        = number
}

variable "min_count" {
  description = "Autoscaling minimum."
  type        = number
}

variable "max_count" {
  description = "Autoscaling maximum."
  type        = number
}

variable "container_insights" {
  description = "Enable Container Insights."
  type        = bool
}

variable "enable_execute_command" {
  description = "Enable ECS Exec."
  type        = bool
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
}

# --- RDS ----------------------------------------------------------------------

variable "db_engine_version" {
  description = "PostgreSQL version."
  type        = string
  default     = "16"
}

variable "db_name" {
  description = "Database name."
  type        = string
  default     = "hotel_db"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "db_allocated_storage" {
  description = "Initial storage (GiB)."
  type        = number
}

variable "db_max_allocated_storage" {
  description = "Storage autoscaling ceiling (GiB)."
  type        = number
}

variable "db_multi_az" {
  description = "Multi-AZ standby."
  type        = bool
}

variable "db_backup_retention_days" {
  description = "Automated backup retention (days)."
  type        = number
}

variable "db_deletion_protection" {
  description = "Deletion protection (also controls the final snapshot)."
  type        = bool
}

variable "db_apply_immediately" {
  description = "Apply DB changes immediately."
  type        = bool
}

variable "db_performance_insights" {
  description = "Enable Performance Insights."
  type        = bool
}
