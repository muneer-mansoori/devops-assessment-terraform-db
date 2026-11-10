variable "name" {
  description = "Name prefix (e.g. hotel-booking-dev)."
  type        = string
}

variable "vpc_id" {
  description = "VPC the database lives in."
  type        = string
}

variable "database_subnet_ids" {
  description = "Isolated subnets for the DB subnet group (at least two AZs)."
  type        = list(string)

  validation {
    condition     = length(var.database_subnet_ids) >= 2
    error_message = "RDS needs subnets in at least two availability zones."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect (the ECS task security group). Nothing else can reach the DB."
  type        = list(string)
}

variable "engine_version" {
  description = "PostgreSQL engine version (major or major.minor)."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "hotel_db"
}

variable "master_username" {
  description = "Master username. The password is generated and stored in Secrets Manager by RDS."
  type        = string
  default     = "hotel_admin"
}

variable "port" {
  description = "PostgreSQL port."
  type        = number
  default     = 5432
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
}

variable "max_allocated_storage" {
  description = "Upper bound for storage autoscaling in GiB."
  type        = number
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for storage encryption. Null uses the AWS-managed RDS key."
  type        = string
  default     = null
}

variable "multi_az" {
  description = "Run a synchronous standby in a second AZ."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Automated backup (PITR) retention in days."
  type        = number

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35 (0 would disable backups)."
  }
}

variable "deletion_protection" {
  description = "Block deletes and take a final snapshot on destroy."
  type        = bool
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of in the maintenance window."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights."
  type        = bool
  default     = false
}

variable "slow_query_log_ms" {
  description = "Log statements slower than this many milliseconds (-1 disables)."
  type        = number
  default     = 500
}

variable "tags" {
  description = "Tags applied to every resource in the module."
  type        = map(string)
  default     = {}
}
