# ============================================================
# DoclingGPU - Terraform Deployment
# IBM Cloud Code Engine + COS Infrastructure
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = ">= 1.65.0"
    }
  }

  # Uncomment to use IBM Cloud Schematics as backend
  # backend "http" {}
}

# ============================================================
# Provider
# ============================================================
provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.region
}

# ============================================================
# Data Sources
# ============================================================
data "ibm_resource_group" "rg" {
  name = var.resource_group
}

# ============================================================
# Cloud Object Storage
# ============================================================
resource "ibm_resource_instance" "cos" {
  name              = "${var.prefix}-cos"
  resource_group_id = data.ibm_resource_group.rg.id
  service           = "cloud-object-storage"
  plan              = "standard"
  location          = "global"

  tags = var.tags
}

resource "ibm_cos_bucket" "input" {
  bucket_name          = "${var.prefix}-input-${random_id.suffix.hex}"
  resource_instance_id = ibm_resource_instance.cos.id
  region_location      = var.region
  storage_class        = "smart"

  lifecycle {
    prevent_destroy = false
  }
}

resource "ibm_cos_bucket" "output" {
  bucket_name          = "${var.prefix}-output-${random_id.suffix.hex}"
  resource_instance_id = ibm_resource_instance.cos.id
  region_location      = var.region
  storage_class        = "smart"

  lifecycle {
    prevent_destroy = false
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# ============================================================
# Code Engine Project
# ============================================================
resource "ibm_code_engine_project" "main" {
  name              = "${var.prefix}-project"
  resource_group_id = data.ibm_resource_group.rg.id
}

# ============================================================
# Code Engine Secrets
# ============================================================
resource "ibm_code_engine_secret" "app_secrets" {
  project_id = ibm_code_engine_project.main.project_id
  name       = "doclinggpu-secrets"
  format     = "generic"

  data = {
    SECRET_KEY      = var.app_secret_key
    CE_REGION       = var.region
    COS_INPUT_BUCKET  = ibm_cos_bucket.input.bucket_name
    COS_OUTPUT_BUCKET = ibm_cos_bucket.output.bucket_name
  }
}

resource "ibm_code_engine_secret" "registry" {
  project_id = ibm_code_engine_project.main.project_id
  name       = "doclinggpu-registry"
  format     = "registry"

  data = {
    server   = var.registry_server
    username = "iamapikey"
    password = var.ibmcloud_api_key
    email    = var.registry_email
  }
}

# ============================================================
# Code Engine Application (Web App)
# ============================================================
resource "ibm_code_engine_app" "webapp" {
  project_id = ibm_code_engine_project.main.project_id
  name       = "${var.prefix}-webapp"

  image_reference = var.webapp_image
  image_secret    = ibm_code_engine_secret.registry.name

  scale_min_instances = 0
  scale_max_instances = var.webapp_max_instances
  scale_cpu_limit     = "1"
  scale_memory_limit  = "4G"
  scale_request_timeout = 300

  run_env_variables {
    type  = "literal"
    name  = "PROCESSING_MODE"
    value = "fleet-gpu"
  }

  run_env_variables {
    type  = "literal"
    name  = "CE_REGION"
    value = var.region
  }

  run_env_variables {
    type  = "literal"
    name  = "CE_INPUT_STORE"
    value = "fleet-input-store"
  }

  run_env_variables {
    type  = "literal"
    name  = "CE_OUTPUT_STORE"
    value = "fleet-output-store"
  }

  run_env_variables {
    type  = "literal"
    name  = "CE_FLEET_TASK_STORE"
    value = "fleet-task-store"
  }

  run_env_variables {
    type  = "literal"
    name  = "CE_FLEET_SUBNETPOOL"
    value = "fleet-subnetpool"
  }

  run_env_variables {
    type       = "secret_key_ref"
    name       = "SECRET_KEY"
    reference  = ibm_code_engine_secret.app_secrets.name
    key        = "SECRET_KEY"
  }

  run_env_variables {
    type       = "secret_key_ref"
    name       = "COS_INPUT_BUCKET"
    reference  = ibm_code_engine_secret.app_secrets.name
    key        = "COS_INPUT_BUCKET"
  }

  run_env_variables {
    type       = "secret_key_ref"
    name       = "COS_OUTPUT_BUCKET"
    reference  = ibm_code_engine_secret.app_secrets.name
    key        = "COS_OUTPUT_BUCKET"
  }

  depends_on = [
    ibm_code_engine_secret.app_secrets,
    ibm_code_engine_secret.registry
  ]
}

# ============================================================
# Outputs
# ============================================================
output "project_id" {
  description = "Code Engine project ID"
  value       = ibm_code_engine_project.main.project_id
}

output "webapp_url" {
  description = "Web application URL"
  value       = ibm_code_engine_app.webapp.endpoint
}

output "cos_input_bucket" {
  description = "COS input bucket name"
  value       = ibm_cos_bucket.input.bucket_name
}

output "cos_output_bucket" {
  description = "COS output bucket name"
  value       = ibm_cos_bucket.output.bucket_name
}

output "cos_instance_id" {
  description = "COS instance CRN"
  value       = ibm_resource_instance.cos.crn
}