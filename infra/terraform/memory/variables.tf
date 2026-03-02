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

variable "memory_name" {
  type        = string
  description = "Name for the memory resource"
  default = "agentvault_memory"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.memory_name))
    error_message = "Memory name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "description" {
  type        = string
  description = "Description for the memory resource"
  default     = "Memory for my agent"
}

variable "event_expiry_days" {
  type        = number
  description = "Number of days to retain events (7-365)"
  default     = 7

  validation {
    condition     = var.event_expiry_days >= 7 && var.event_expiry_days <= 365
    error_message = "Event expiry days must be between 7 and 365."
  }
}

variable "strategies" {
  type = list(object({
    name        = string
    type        = string
    description = optional(string, "")
    namespaces  = optional(list(string), ["default"])
    configuration = optional(object({
      type = string
      consolidation = optional(object({
        append_to_prompt = string
        model_id         = string
      }))
      extraction = optional(object({
        append_to_prompt = string
        model_id         = string
      }))
    }))
  }))
  description = "List of memory strategies. Valid types: SEMANTIC, SUMMARIZATION, USER_PREFERENCE, CUSTOM. Max 1 of each built-in type, max 6 total."
  default     = []

  validation {
    condition     = length(var.strategies) <= 6
    error_message = "Maximum of 6 strategies allowed per memory."
  }

  validation {
    condition = alltrue([
      for s in var.strategies : contains(["SEMANTIC", "SUMMARIZATION", "USER_PREFERENCE", "CUSTOM"], s.type)
    ])
    error_message = "Strategy type must be one of: SEMANTIC, SUMMARIZATION, USER_PREFERENCE, CUSTOM."
  }

  validation {
    condition = length([for s in var.strategies : s.type if s.type == "SEMANTIC"]) <= 1
    error_message = "Only one SEMANTIC strategy allowed per memory."
  }

  validation {
    condition = length([for s in var.strategies : s.type if s.type == "SUMMARIZATION"]) <= 1
    error_message = "Only one SUMMARIZATION strategy allowed per memory."
  }

  validation {
    condition = length([for s in var.strategies : s.type if s.type == "USER_PREFERENCE"]) <= 1
    error_message = "Only one USER_PREFERENCE strategy allowed per memory."
  }

  validation {
    condition = alltrue([
      for s in var.strategies : s.type != "CUSTOM" || s.configuration != null
    ])
    error_message = "CUSTOM strategy type requires configuration block."
  }

  validation {
    condition = alltrue([
      for s in var.strategies : s.type == "CUSTOM" || s.configuration == null
    ])
    error_message = "Configuration block is only allowed for CUSTOM strategy type."
  }
}
