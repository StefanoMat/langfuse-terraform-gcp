terraform {
  backend "gcs" {
    bucket = "langfuse-hml-terraform-state"  # Será criado pelo bootstrap
    prefix = "kaeferdev/state"
  }
}
