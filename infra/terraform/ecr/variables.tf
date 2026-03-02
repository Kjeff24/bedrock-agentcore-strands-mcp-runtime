variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project identifier used in resource names."
  type        = string
  default     = "agentvault_agent"
}

variable "environment_name" {
  type        = string
  default     = "prod"
  description = "Environment name"
}

variable "repository_name" {
  type        = string
  description = "Name of the ECR repository"
  default = "agentvault_agent"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_/]*$", var.repository_name))
    error_message = "Repository name must start with a lowercase letter or number and contain only lowercase letters, numbers, hyphens, underscores, and forward slashes."
  }
}

variable "force_delete" {
  type = bool
  description = "Delete the repository even if it contains images"
  default = true
  
}

