variable "aws_region" {
  description = "AWS region used for primary resources."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Short workload name used for resource naming."
  type        = string
  default     = "serverless-event-api"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name))
    error_message = "Use 3-32 lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "stage", "prod"], var.environment)
    error_message = "Environment must be dev, test, stage, or prod."
  }
}

variable "tags" {
  description = "Additional tags merged into all supported resources."
  type        = map(string)
  default     = {}
}

variable "lambda_runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.12"
}

variable "lambda_memory_mb" {
  description = "Lambda memory in MB."
  type        = number
  default     = 256
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 10
}

variable "api_stage_name" {
  description = "HTTP API stage name."
  type        = string
  default     = "$default"
}
