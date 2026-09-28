terraform {
  # import blocks with for_each need Terraform >= 1.7.
  required_version = ">= 1.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.4"
    }
  }

  # Local state on purpose (demo project, single operator). For a team, switch to:
  # backend "gcs" { bucket = "<project>-tfstate", prefix = "roastfolio" }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "this" {
  project_id = var.project_id
}
