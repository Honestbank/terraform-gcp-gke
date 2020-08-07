provider "google" {
  # Use 'export GCLOUD_CREDENTIALS="PATH_TO_KEYFILE_JSON"' instead of
  # committing a keyfile to versioning
  # credentials = file("PATH_TO_KEYFILE_JSON")
  project     = var.project
  region      = var.region
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
  version = "~> 3.29.0"
}

# provider "google-beta" {
#   # Use 'export GCLOUD_CREDENTIALS="PATH_TO_KEYFILE_JSON"' instead of
#   # committing a keyfile to versioning
#   # credentials = file("PATH_TO_KEYFILE_JSON")
#   project = var.project
#   region  = var.region

#   scopes = [
#     # Default scopes
#     "https://www.googleapis.com/auth/compute",
#     "https://www.googleapis.com/auth/cloud-platform",
#     "https://www.googleapis.com/auth/ndev.clouddns.readwrite",
#     "https://www.googleapis.com/auth/devstorage.full_control",

#     # Required for google_client_openid_userinfo
#     "https://www.googleapis.com/auth/userinfo.email",
#   ]
# }

terraform {
  required_version = "~> 0.12.28"
}

provider "null" {
  version = "~> 2.1"
}

provider "random" {
  version = "~> 2.2"
}

provider "kubernetes" {
  version = "~> 1.11.0"

  load_config_file = false

  host                   = module.primary-cluster.endpoint
  cluster_ca_certificate = base64decode(module.primary-cluster.ca_certificate)
  token                  = data.google_client_config.client.access_token
}

provider "helm" {
  # Use provider with Helm 3.x support
  version = "~> 1.2.4"

  kubernetes {
    load_config_file = false
    
    host                   = module.primary-cluster.endpoint
    cluster_ca_certificate = base64decode(module.primary-cluster.ca_certificate)
    token                  = data.google_client_config.client.access_token
  }
}

provider "template" {
  version = "~> 2.1"
}

module "primary-cluster" {
  # google-beta provider has an update-variant option
  # source                     = "./modules/terraform-google-kubernetes-engine/modules/beta-public-cluster-update-variant"
  source = "./modules/terraform-google-kubernetes-engine/"

  project_id                 = var.project
  name                       = local.cluster_name
  region                     = var.region
  zones                      = var.zones
  network                    = module.primary-cluster-networking.network_name
  subnetwork                 = module.primary-cluster-networking.subnets_names[0]
  ip_range_pods              = module.primary-cluster-networking.subnets_secondary_ranges[0][0]["range_name"]
  ip_range_services          = module.primary-cluster-networking.subnets_secondary_ranges[0][1]["range_name"]
  http_load_balancing        = false
  horizontal_pod_autoscaling = false
  network_policy             = true

  //Required for GKE-installed Istio
  create_service_account = true

  # Google Container Registry access
  registry_project_id   = var.project
  grant_registry_access = true

  # google-beta provider allows setting a Release Channel
  # release_channel = var.release_channel

  node_pools = [
    {
      name            = "pool-01"
      machine_type    = var.machine_type
      min_count       = var.minimum_node_count
      max_count       = var.maximum_node_count
      node_count      = 1
      local_ssd_count = 1
      disk_size_gb    = 200
      disk_type       = "pd-standard"
      image_type      = "COS"
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
}

module "primary-cluster-networking" {
  source       = "./modules/terraform-google-network"
  project_id   = var.project
  network_name = local.network_name
  routing_mode = "REGIONAL"

  subnets = [
    {
      subnet_name   = local.primary_subnet_name
      subnet_ip     = "10.10.0.0/16"
      subnet_region = var.region
    },
  ]

  secondary_ranges = {
    "${local.primary_subnet_name}" = [
      {
        range_name = local.pods_ip_range_name
        # ip_cidr_range = "192.168.0.0/18"
        ip_cidr_range = "10.11.0.0/16"
      },
      {
        range_name = local.services_ip_range_name
        # ip_cidr_range = "192.168.64.0/18"
        ip_cidr_range = "10.12.0.0/16"
      },
    ]
  }
}

# We use this data provider to expose an access token for communicating with the GKE cluster.
data "google_client_config" "client" {}

data "google_container_cluster" "current_cluster" {
  name     = module.primary-cluster.name
  location = module.primary-cluster.location
}

# set up the gcloud command line tools
resource "null_resource" "setup_gcloud_cli" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOH
  curl https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-302.0.0-linux-x86_64.tar.gz | tar xz
  cat <<< '${var.google_credentials}' > google_credentials_keyfile.json
  ./google-cloud-sdk/bin/gcloud auth activate-service-account --key-file google_credentials_keyfile.json --quiet
  EOH
    # Use environment variables to allow custom kubectl config paths
    //    environment = {
    //      KUBECONFIG = local_file.kubeconfig.filename != "" ? local_file.kubeconfig.filename : ""
    //    }

    interpreter = [
      "/bin/bash",
    "-c"]
  }

  depends_on = [
  module.primary-cluster]
}

# download kubectl
resource "null_resource" "download_kubectl" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOH
if ! command -v kubectl; then curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && alias kubectl="./kubectl"; fi;
EOH
  }

  depends_on = [
  null_resource.setup_gcloud_cli]
}

# get kubeconfig
resource "null_resource" "configure_kubectl" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOH
      ./google-cloud-sdk/bin/gcloud container clusters get-credentials "${module.primary-cluster.name}" --region "${var.region}" --project "${var.project}" --quiet
EOH
  }

  depends_on = [
  null_resource.download_kubectl]
}

# Install Istio Operator using istioctl
resource "null_resource" "install_istio_operator" {
  provisioner "local-exec" {
    command = <<EOH
if ! command -v kubectl; then alias kubectl=./kubectl; fi;
curl -sL https://istio.io/downloadIstioctl | sh -
export PATH=$PATH:$HOME/.istioctl/bin
istioctl operator init
kubectl label namespace default istio-injection=enabled
EOH
  }

  depends_on = [
  null_resource.configure_kubectl]
}

# Set up Kiali credentials
resource "null_resource" "set_kiali_credentials" {
  provisioner "local-exec" {
    command = <<EOH
if ! command -v kubectl; then alias kubectl=./kubectl; fi;
kubectl create ns istio-system
KIALI_USERNAME=$(printf "${var.kiali_username}" | base64)
echo "Kiali Username (base64): "$KIALI_USERNAME
KIALI_PASSPHRASE=$(printf "${var.kiali_passphrase}" | base64)
echo "Kiali Passphrase (base64): "$KIALI_PASSPHRASE
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: kiali
  namespace: istio-system
  labels:
    app: kiali
type: Opaque
data:
  username: $KIALI_USERNAME
  passphrase: $KIALI_PASSPHRASE
EOF
EOH
  }

  depends_on = [
    null_resource.configure_kubectl,
  null_resource.install_istio_operator]
}

# Install IstioOperator resource manifest to trigger mesh installation
resource "null_resource" "install_IstioOperator_manifest" {
  provisioner "local-exec" {
    command = <<EOH
if ! command -v kubectl; then alias kubectl=./kubectl; fi;
cat <<EOF | kubectl apply -f -
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  namespace: istio-system
  name: honestbank-istio-mesh
spec:
  profile: default
  addonComponents:
    grafana:
      enabled: true
    kiali:
      enabled: true
EOF
EOH
  }

  depends_on = [
    null_resource.configure_kubectl,
  null_resource.set_kiali_credentials]
}

# Install Elastic operator
resource "null_resource" "install_Elastic_operator" {
  provisioner "local-exec" {
    command = <<EOH
if ! command -v kubectl; then alias kubectl=./kubectl; fi;
kubectl apply -f https://download.elastic.co/downloads/eck/1.2.0/all-in-one.yaml
EOH
  }

  depends_on = [
  null_resource.configure_kubectl]
}

# Install Elasticsearch and Kibana
resource "null_resource" "install_Elastic_resources" {
  provisioner "local-exec" {
    command = <<EOH
if ! command -v kubectl; then alias kubectl=./kubectl; fi;
kubectl create -f "${path.module}/modules/elastic/elastic-basic-cluster.yaml"
kubectl create -f "${path.module}/modules/elastic/elastic-filebeat.yaml"
kubectl create -f "${path.module}/modules/elastic/elastic-kibana.yaml"
EOH
  }

  depends_on = [
    null_resource.configure_kubectl,
  null_resource.install_Elastic_operator]
}

# Install Jaeger Operator
resource "helm_release" "jaeger" {
  name             = "telemetry"
  repository       = "https://jaegertracing.github.io/helm-charts"
  chart            = "jaeger-operator"
  namespace        = "observability"
  create_namespace = true

  set {
    name  = "jaeger.create"
    value = "true"
  }

  set {
    name  = "rbac.clusterRole"
    value = "true"
  }

  depends_on = [module.primary-cluster]
}
