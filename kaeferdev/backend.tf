terraform {
  backend "gcs" {
    bucket = "langfuse-prd-487000-terraform-state"
    prefix = "prd/state"
  }
}
