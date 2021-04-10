provider "google" {
  alias       = "compute"
  project     = var.google_project
  region      = var.google_region
  credentials = var.google_credentials

  scopes = [
    # Default scopes
    "https://www.googleapis.com/auth/compute",
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/ndev.clouddns.readwrite",
    "https://www.googleapis.com/auth/devstorage.full_control",

    # Required for google_client_openid_userinfo
    "https://www.googleapis.com/auth/userinfo.email",
  ]
}

provider "google-beta" {
  alias       = "compute-beta"
  project     = var.google_project
  region      = var.google_region
  credentials = var.google_credentials
}

provider "google" {
  alias       = "vpc"
  project     = var.shared_vpc_host_google_project
  region      = var.google_region
  credentials = var.shared_vpc_host_google_credentials
}

terraform {
  required_version = ">= 0.14.0"

  required_providers {
    external = {
      version = "~> 1.2.0"
    }

    google = {
      version = ">= 3.51.0, < 4.0.0"
    }

    google-beta = {
      version = ">= 3.51.0, < 4.0.0"
      source  = "hashicorp/google-beta"
    }

    helm = {
      # Use provider with Helm 3.x support
      version = "~> 1.3.0"
    }

    kubernetes = {
      version = "~> 1.13"
    }

    null = {
      version = ">=2.1.2, <= 3.0"
      source  = "hashicorp/null"
    }

    random = {
      version = "~> 3.0"
    }

    template = {
      version = "~> 2.2"
    }
  }
}

provider "null" {
}

provider "random" {
}

provider "template" {
}

resource "random_id" "run_id" {
  byte_length = 4
}

# Shared VPC Permissions
data "google_project" "service_project" {
  provider = google.compute
}

data "google_project" "host_project" {
  provider = google.vpc
}

locals {
  project_number = data.google_project.service_project.number
  project_id     = data.google_project.service_project.project_id
}

resource "google_project_iam_binding" "compute-network-user" {
  provider = google.vpc
  project  = data.google_project.host_project.project_id
  role     = "roles/compute.networkUser"

  members = [
    "serviceAccount:${format("service-%s@container-engine-robot.iam.gserviceaccount.com", local.project_number)}",
    "serviceAccount:${format("%s@cloudservices.gserviceaccount.com", local.project_number)}",
  ]
}

# VPC
module "shared-vpc" {
  source = "./modules/terraform-google-network"

  project_id = var.shared_vpc_host_google_project
  network_name = "${local.cluster_name}-vpc"
  routing_mode = "REGIONAL"

  subnets = [
    {
      subnet_name = "${local.cluster_name}-subnet"
      subnet_ip = "10.10.0.0/16"
      subnet_region = "asia-southeast2"
      subnet_private_access = "true"
      subnet_flow_logs = "off"
    }
  ]

  secondary_ranges = {
    "${local.cluster_name}-subnet" = [
      {
        range_name = "private-vpc-pods"
        ip_cidr_range = "10.20.0.0/16"
      },
      {
        range_name = "private-vpc-services"
        ip_cidr_range = "10.30.0.0/16"
      }
    ]
  }
}

# GKE Cluster Config
module "primary-cluster" {
  providers = {
    google      = google.compute
    google-beta = google-beta.compute-beta
  }
  source = "./modules/terraform-google-kubernetes-engine/modules/beta-private-cluster-update-variant"

  # Disables downloading of gcloud CLI and the wait_for_cluster.sh script
  # Also breaks stub domains
  skip_provisioners = true

  project_id                 = var.google_project
  name                       = local.cluster_name
  region                     = var.google_region
  zones                      = var.zones
  network                    = local.network_name
  network_project_id         = var.shared_vpc_host_google_project
  subnetwork                 = local.primary_subnet_name
  ip_range_pods              = local.pods_ip_range_name
  ip_range_services          = local.services_ip_range_name
  http_load_balancing        = true
  horizontal_pod_autoscaling = false
  create_service_account     = true
  remove_default_node_pool   = true
  release_channel            = var.release_channel

  // Private nodes better control public exposure, and reduce
  // the ability of nodes to reach to the Internet without
  // additional configurations.
  enable_private_nodes        = true
  enable_shielded_nodes       = true
  enable_intranode_visibility = true
  add_cluster_firewall_rules  = true

  # Required for GKE-installed Istio
  network_policy = true

  // Basic Auth disabled
  basic_auth_username = ""
  basic_auth_password = ""

  // Disable logging and monitoring
  logging_service    = "none"
  monitoring_service = "none"

  // Storage
  gce_pd_csi_driver = true

  node_pools = [
    {
      name            = "pool-01"
      machine_type    = var.machine_type
      min_count       = var.minimum_node_count
      max_count       = var.maximum_node_count
      node_count      = var.initial_node_count
      max_surge       = var.maximum_node_count
      max_unavailable = 1
      local_ssd_count = 0
      disk_size_gb    = 200
      disk_type       = "pd-standard"
      image_type      = "COS_CONTAINERD"
      auto_repair     = true
      auto_upgrade    = true
      preemptible     = false
    },
  ]

  node_pools_oauth_scopes = {
    all = [
      "https://www.googleapis.com/auth/trace.append",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/logging.write",
    ]
  }

  depends_on = [module.shared-vpc]
}

# We use this data provider to expose an access token for communicating with the GKE cluster.
data "google_client_config" "default" {
  provider = google-beta.compute-beta
}

data "google_container_cluster" "current_cluster" {
  provider = google-beta.compute-beta

  name     = module.primary-cluster.name
  location = module.primary-cluster.location
}

# Networking - create a NAT gateway for the cluster
resource "google_compute_address" "cloud_nat_ip" {
  provider = google.vpc
  name     = "gke-nat"
}

module "cloud_router" {
  source  = "terraform-google-modules/cloud-router/google"
  version = "~> 0.4"

  name    = "gke-cluster-cloud-router"
  project = var.shared_vpc_host_google_project
  network = local.network_name
  region  = var.google_region

  nats = [{
    name = "gke-cluster-cloud--nat"
  }]

  depends_on = [module.shared-vpc]
}

# Providers for Bootstrap
provider "helm" {
  kubernetes {
    load_config_file = false

    host                   = "https://${module.primary-cluster.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.primary-cluster.ca_certificate)
  }
}

provider "kubernetes" {
  load_config_file = false

  host                   = "https://${module.primary-cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.primary-cluster.ca_certificate)

}
