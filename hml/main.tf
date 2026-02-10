provider "google" {
  region = "us-central1"
}

module "langfuse" {
  source = "../"

  domain = "langfuse-hml.kaeferdev.com"

  name = "langfuse"

  subnetwork_cidr      = "10.0.0.0/16"
  kubernetes_namespace = "langfuse"

  # HML: recursos menores para economia
  database_instance_tier              = "db-f1-micro"
  database_instance_availability_type = "ZONAL"
  database_instance_edition           = "ENTERPRISE"

  cache_tier           = "BASIC"
  cache_memory_size_gb = 1

  deletion_protection = false

  langfuse_chart_version = "1.5.14"
}

provider "kubernetes" {
  host                   = module.langfuse.cluster_host
  cluster_ca_certificate = module.langfuse.cluster_ca_certificate
  token                  = module.langfuse.cluster_token
}

provider "helm" {
  kubernetes {
    host                   = module.langfuse.cluster_host
    cluster_ca_certificate = module.langfuse.cluster_ca_certificate
    token                  = module.langfuse.cluster_token
  }
}
