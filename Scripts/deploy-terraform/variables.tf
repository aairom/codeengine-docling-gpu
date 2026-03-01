# ============================================================
# DoclingGPU - Terraform Variables
# ============================================================

variable "ibmcloud_api_key" {
  description = "IBM Cloud API key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "IBM Cloud region"
  type        = string
  default     = "eu-de"
  validation {
    condition     = contains(["eu-de", "us-south", "us-east", "eu-gb", "jp-tok", "au-syd", "br-sao", "ca-tor"], var.region)
    error_message = "Region must be a valid IBM Cloud region."
  }
}

variable "resource_group" {
  description = "IBM Cloud resource group name"
  type        = string
  default     = "default"
}

variable "prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "doclinggpu"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.prefix))
    error_message = "Prefix must be 3-21 lowercase alphanumeric characters or hyphens, starting with a letter."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = list(string)
  default     = ["doclinggpu", "code-engine", "docling", "gpu"]
}

variable "app_secret_key" {
  description = "Flask application secret key (generate with: openssl rand -hex 32)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "webapp_image" {
  description = "Container image for the web application"
  type        = string
  default     = "quay.io/doclinggpu/webapp:latest"
}

variable "webapp_max_instances" {
  description = "Maximum number of web app instances"
  type        = number
  default     = 5
  validation {
    condition     = var.webapp_max_instances >= 1 && var.webapp_max_instances <= 50
    error_message = "Max instances must be between 1 and 50."
  }
}

variable "registry_server" {
  description = "Container registry server (e.g. de.icr.io)"
  type        = string
  default     = "de.icr.io"
}

variable "registry_email" {
  description = "Container registry email"
  type        = string
  default     = "user@example.com"
}

variable "fleet_max_scale_gpu" {
  description = "Maximum number of GPU fleet workers"
  type        = number
  default     = 4
}

variable "fleet_max_scale_cpu" {
  description = "Maximum number of CPU fleet workers"
  type        = number
  default     = 8
}

variable "gpu_type" {
  description = "GPU type for fleet workers (l40s or h100)"
  type        = string
  default     = "l40s"
  validation {
    condition     = contains(["l40s", "h100"], var.gpu_type)
    error_message = "GPU type must be l40s or h100."
  }
}