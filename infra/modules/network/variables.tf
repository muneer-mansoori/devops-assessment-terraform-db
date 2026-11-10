variable "name" {
  description = "Name prefix for all network resources (e.g. hotel-booking-dev)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be /16 so each tier gets /24 subnets via cidrsubnet(cidr, 8, n)."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid /16 CIDR block."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across. Listed explicitly so plans are deterministic."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 6
    error_message = "Provide between 2 and 6 AZs (RDS subnet groups and the ALB need at least 2)."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway (cheaper, dev) instead of one per AZ (highly available, prod)."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to CloudWatch Logs."
  type        = bool
  default     = false
}

variable "flow_logs_retention_days" {
  description = "Retention for the VPC flow log group."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to every resource in the module."
  type        = map(string)
  default     = {}
}
