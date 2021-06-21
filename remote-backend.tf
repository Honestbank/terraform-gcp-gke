terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "honestbank"

    workspaces {
      prefix = "terraform-gcp-gke-"
    }
  }

  required_version = ">= 0.13.1"
}

module "gke" {
  source = "./gcp-gke"

  google_project     = var.google_project
  google_region      = var.google_region
  google_credentials = var.google_credentials

  shared_vpc_host_google_project     = var.shared_vpc_host_google_project
  shared_vpc_host_google_credentials = var.shared_vpc_host_google_credentials

  stage           = var.stage
  cluster_purpose = var.cluster_purpose
  cluster_number  = var.cluster_number

  machine_type       = var.machine_type
  minimum_node_count = var.minimum_node_count
  maximum_node_count = var.maximum_node_count
  initial_node_count = var.initial_node_count
}
