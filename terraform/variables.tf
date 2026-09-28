variable "project_id" {
  description = "GCP project that hosts Roastfolio."
  type        = string
}

variable "region" {
  description = "Main region (Cloud Run, Storage, Firestore, Tasks, Artifact Registry, Cloud Build)."
  type        = string
  default     = "us-central1"
}

variable "app" {
  description = "Short name used as a prefix for buckets, services and the Firestore database."
  type        = string
  default     = "roastfolio"
}

variable "docai_location" {
  description = "Document AI multi-region for the Layout Parser processor."
  type        = string
  default     = "us"
}

variable "genai_location" {
  description = "Vertex AI location for the Gemini models."
  type        = string
  default     = "global"
}

variable "gemini_text_model" {
  description = "Gemini model for profile normalization and the roast."
  type        = string
  default     = "gemini-3.8-flash"
}

variable "gemini_image_model" {
  description = "Nano Banana model for the certificate card."
  type        = string
  default     = "gemini-3.1-flash-lite-image"
}

variable "initial_image" {
  description = "Image used only when Terraform creates a Cloud Run service. Cloud Build ships the real images afterwards."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "alert_email" {
  description = "Email that receives the error-rate alert."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository (owner/name) that triggers Cloud Build on push to main."
  type        = string
  default     = "ykro/roastfolio"
}

variable "github_app_installation_id" {
  description = "Cloud Build GitHub App installation id. Leave null on the first apply; fill it after authorizing the connection in the browser."
  type        = number
  default     = null
}

variable "github_token_secret" {
  description = "Regional secret (in var.region) where Cloud Build stored the GitHub OAuth token, e.g. rf-github-github-oauthtoken-xxxxxx. Null until the connection is authorized."
  type        = string
  default     = null
}
