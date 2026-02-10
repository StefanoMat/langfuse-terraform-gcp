# Bootstrap - Execute isso uma vez localmente para configurar o WIF
# Depois disso, a pipeline funciona sem chaves

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository (format: owner/repo)"
  type        = string
}

provider "google" {
  project = var.project_id
}

# Obter informações do projeto
data "google_project" "project" {}

# Bucket para Terraform state
resource "google_storage_bucket" "terraform_state" {
  name          = "${var.project_id}-terraform-state"
  location      = "US"
  force_destroy = false

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
}

# Service Account para GitHub Actions
resource "google_service_account" "github_actions" {
  account_id   = "github-actions-terraform"
  display_name = "GitHub Actions Terraform"
  description  = "Used by GitHub Actions to deploy infrastructure"
}

# Permissões para o Service Account
resource "google_project_iam_member" "github_actions_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Workload Identity Pool
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Identity pool for GitHub Actions"
}

# Workload Identity Provider (OIDC)
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Permitir que o repositório GitHub use o Service Account
resource "google_service_account_iam_member" "github_actions_wif" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# Outputs para configurar no GitHub
output "wif_provider" {
  description = "Workload Identity Provider - adicione como variable WIF_PROVIDER no GitHub"
  value       = "projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
}

output "wif_service_account" {
  description = "Service Account - adicione como variable WIF_SERVICE_ACCOUNT no GitHub"
  value       = google_service_account.github_actions.email
}

output "terraform_state_bucket" {
  description = "Bucket para o Terraform state"
  value       = google_storage_bucket.terraform_state.name
}

output "next_steps" {
  description = "Próximos passos"
  value       = <<-EOT
    
    ✅ Bootstrap completo! Agora:
    
    1. Vá em GitHub → Settings → Secrets and variables → Actions → Variables
    2. Adicione estas variables:
       - WIF_PROVIDER: (valor do output wif_provider acima)
       - WIF_SERVICE_ACCOUNT: (valor do output wif_service_account acima)
    
    3. Atualize o backend no kaeferdev/backend.tf com o bucket:
       bucket = "${google_storage_bucket.terraform_state.name}"
    
    4. Migre o state: cd kaeferdev && terraform init -migrate-state
    
    5. Push para o GitHub e a pipeline vai funcionar!
  EOT
}
