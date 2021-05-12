locals {
  cluster_name = "${var.stage}-${var.cluster_purpose}-${var.cluster_number}-${random_id.run_id.hex}"

  network_name           = "tfmanaged-shared-vpc"
  primary_subnet_name    = "tfmanaged-shared-vpc-subnet-01"
  pods_ip_range_name     = "tfmanaged-shared-vpc-subnet-01-01"
  services_ip_range_name = "tfmanaged-shared-vpc-subnet-01-02"


  //  network_name           = "${var.stage}-private-vpc"
  //  primary_subnet_name    = "${var.stage}-private-vpc-subnet"
  //  pods_ip_range_name     = "${var.stage}-private-vpc-pods"
  //  services_ip_range_name = "${var.stage}-private-vpc-services"
}

variable "google_project" {
  description = "The GCP project to use for this run"
}

variable "google_credentials" {
  description = "Contents of a JSON keyfile of an account with write access to the project"
}

variable "shared_vpc_host_google_project" {
  description = "The GCP project that hosts the shared VPC to place resources into"
}

variable "shared_vpc_host_google_credentials" {
  description = "Service Account with access to shared_vpc_host_google_project networks"
}

variable "google_region" {
  description = "GCP region used to create all resources in this run"
}

variable "stage" {
  description = "Stage: [test, dev, prod...] used as prefix for all resources."
  default     = "test"
}

variable "cluster_purpose" {
  description = "Name to assign to GKE cluster built in this run."
  default     = "tf-gke-template"
}

variable "cluster_number" {
  default = 00
}

variable "zones" {
  description = "Zones for the VMs in the cluster. Default is set to Jakarta (all zones)."
}

variable "release_channel" {
  type        = string
  description = "(Beta) The release channel of this cluster. Accepted values are `UNSPECIFIED`, `RAPID`, `REGULAR` and `STABLE`. Defaults to `REGULAR`."
  default     = "RAPID"
}

variable "minimum_node_count" {
  default     = 1
  description = "Minimum nodes for the node pool per-zone."
}

variable "maximum_node_count" {
  default     = 1
  description = "Maximum nodes for the node pool per-zone."
}

variable "initial_node_count" {
  default     = 1
  description = "Initial node count, per-zone for regional clusters."
}

variable "machine_type" {
  default     = "n1-standard-2"
  description = "Machine types to use for the node pool."
}
