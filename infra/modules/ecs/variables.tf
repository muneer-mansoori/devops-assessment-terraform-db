variable "name" {
  description = "Name prefix (e.g. hotel-booking-dev). Keep it short: ALB and target group names are limited to 32 characters."
  type        = string

  validation {
    condition     = length(var.name) <= 28
    error_message = "name must be 28 characters or fewer so '<name>-alb' and '<name>-tg' fit AWS limits."
  }
}

variable "environment" {
  description = "Environment name passed to the container as APP_ENV."
  type        = string
}

variable "region" {
  description = "AWS region, used for the awslogs driver."
  type        = string
}

variable "vpc_id" {
  description = "VPC to deploy into."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for the Fargate tasks."
  type        = list(string)
}

variable "db_subnet_cidrs" {
  description = "Database subnet CIDRs that tasks may reach on db_port."
  type        = list(string)
}

variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "certificate_arn" {
  description = "ACM certificate ARN. When set, adds an HTTPS listener and redirects HTTP to HTTPS."
  type        = string
  default     = null
}

variable "alb_deletion_protection" {
  description = "Protect the ALB against accidental deletion."
  type        = bool
  default     = false
}

variable "container_image" {
  description = "Container image for the application."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "ALB target group health check path."
  type        = string
  default     = "/"
}

variable "task_cpu" {
  description = "Fargate task CPU units (256, 512, 1024, ...)."
  type        = number

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.task_cpu)
    error_message = "task_cpu must be a valid Fargate CPU value."
  }
}

variable "task_memory" {
  description = "Fargate task memory in MiB (must be valid for the chosen CPU)."
  type        = number
}

variable "desired_count" {
  description = "Initial number of running tasks."
  type        = number
}

variable "min_count" {
  description = "Autoscaling minimum task count."
  type        = number
}

variable "max_count" {
  description = "Autoscaling maximum task count."
  type        = number

  validation {
    condition     = var.max_count >= 1
    error_message = "max_count must be at least 1."
  }
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights on the cluster."
  type        = bool
  default     = true
}

variable "enable_execute_command" {
  description = "Allow ECS Exec into running tasks (for debugging)."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the application logs."
  type        = number
  default     = 30
}

variable "db_host" {
  description = "Database hostname passed to the application."
  type        = string
}

variable "db_port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Database name passed to the application."
  type        = string
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the database username and password."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource in the module."
  type        = map(string)
  default     = {}
}
