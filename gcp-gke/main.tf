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

  # Depends on the primary_cluster_auth module, currently unused in favor of gcloud CLI via shell-exec
  load_config_file = false

  cluster_ca_certificate = module.primary_cluster_auth.cluster_ca_certificate
  host                   = module.primary_cluster_auth.host
  token                  = module.primary_cluster_auth.token

  # host  = "https://${data.google_container_cluster.current_cluster.endpoint}"
  # token = data.google_client_config.provider.access_token
  # cluster_ca_certificate = base64decode(
  #   data.google_container_cluster.current_cluster.master_auth[0].cluster_ca_certificate,
  # )
}

provider "helm" {
  # Use provider with Helm 3.x support
  version = "~> 1.2.3"
}

provider "template" {
  version = "~> 2.1"
}

module "primary-cluster" {
  # google-beta
  # source                     = "./modules/terraform-google-kubernetes-engine/modules/beta-public-cluster-update-variant"
  source                     = "./modules/terraform-google-kubernetes-engine/"
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
  network_policy             = true //Required for GKE-installed Istio
  create_service_account     = true

  # Google Container Registry access
  registry_project_id   = var.project
  grant_registry_access = true

  # google-beta provider options
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

### Use this to get kubeconfig data to connect to the cluster
### Currently using the shell-exec provisioner and gcloud CLI instead
# module "primary-cluster-auth" {
module "primary_cluster_auth" {
  source = "./modules/terraform-google-kubernetes-engine/modules/auth"

  project_id   = var.project
  cluster_name = module.primary-cluster.name
  location     = module.primary-cluster.location
}

### `kubeconfig` output
//resource "local_file" "kubeconfig" {
//  content  = module.primary_cluster_auth.kubeconfig_raw
//  filename = "${path.module}/kubeconfig"
//}

# We use this data provider to expose an access token for communicating with the GKE cluster.
data "google_client_config" "client" {}

# Use this datasource to access the Terraform account's email for Kubernetes permissions.
data "google_client_openid_userinfo" "terraform_user" {}

data "google_container_cluster" "current_cluster" {
  name     = module.primary-cluster.name
  location = module.primary-cluster.location
}

# configure kubectl with the credentials of the GKE cluster
resource "null_resource" "configure_kubectl" {
  provisioner "local-exec" {
    command = <<EOH
  curl https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-302.0.0-linux-x86_64.tar.gz | tar xz
  ./google-cloud-sdk/bin/gcloud auth activate-service-account --key-file "${var.google_credentials}" --quiet
  ./google-cloud-sdk/bin/gcloud container clusters get-credentials "${module.primary-cluster.name}" --region "${var.region}" --project "${var.project}" --quiet
  EOH
    # Use environment variables to allow custom kubectl config paths
    //    environment = {
    //      KUBECONFIG = local_file.kubeconfig.filename != "" ? local_file.kubeconfig.filename : ""
    //    }
  }

  depends_on = [module.primary-cluster]
}

# Install Istio Operator using istioctl
resource "null_resource" "install_istio_operator" {
  provisioner "local-exec" {
    command = <<EOH
curl -sL https://istio.io/downloadIstioctl | sh -
export PATH=$PATH:$HOME/.istioctl/bin
istioctl operator init
kubectl label namespace default istio-injection=enabled
EOH
  }

  depends_on = [null_resource.configure_kubectl]
}

# Set up Kiali credentials
resource "null_resource" "set_kiali_credentials" {
  provisioner "local-exec" {
    command = <<EOH
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

  depends_on = [null_resource.install_istio_operator]
}

# Install IstioOperator resource manifest to trigger mesh installation
resource "null_resource" "install_IstioOperator_manifest" {
  provisioner "local-exec" {
    command = <<EOH
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

  depends_on = [null_resource.set_kiali_credentials]
}

# Install Elastic operator
resource "null_resource" "install_Elastic_operator" {
  provisioner "local-exec" {
    command = <<EOH
kubectl apply -f https://download.elastic.co/downloads/eck/1.2.0/all-in-one.yaml
EOH
  }

  depends_on = [null_resource.configure_kubectl]
}

# Install Elasticsearch and Kibana
resource "null_resource" "install_Elastic_resources" {
  provisioner "local-exec" {
    command     = <<EOH
kubectl create -f 'modules/elastic/elastic-basic-cluster.yaml'
kubectl create -f 'modules/elastic/elastic-filebeat.yaml'
kubectl create -f 'modules/elastic/elastic-kibana.yaml'
EOH
    working_dir = path.module
  }

  depends_on = [null_resource.install_Elastic_operator]
}

data "kubernetes_secret" "elastic_password" {
  metadata {
    name = "logging-es-elastic-user"
  }

  depends_on = [null_resource.install_Elastic_resources]
}

resource "helm_release" "filebeat" {
  name       = "filebeat"
  repository = "https://helm.elastic.co"
  chart      = "filebeat"
  version    = "7.8.0"
  namespace  = "kube-system"

  values = [
    "${file("modules/elastic/filebeat-values.yaml")}"
  ]

  set {
    name  = "extraEnvs[0].name"
    value = "ELASTICSEARCH_HOST"
    type  = "string"
  }

  set {
    name  = "extraEnvs[0].value"
    value = "logging-es-http.default.svc.cluster.local"
    type  = "string"
  }

  set {
    name  = "extraEnvs[1].name"
    value = "ELASTICSEARCH_USERNAME"
    type  = "string"
  }

  set {
    name  = "extraEnvs[1].value"
    value = "elastic"
    type  = "string"
  }

  set {
    name  = "extraEnvs[2].name"
    value = "ELASTICSEARCH_PASSWORD"
    type  = "string"
  }

  set {
    name  = "extraEnvs[2].value"
    value = data.kubernetes_secret.elastic_password.data["elastic"]
    type  = "string"
  }

  depends_on = [data.kubernetes_secret.elastic_password]
}

### Jaeger
resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
  }
}

resource "helm_release" "jaeger" {
  name       = "jaeger"
  repository = "https://jaegertracing.github.io/helm-charts"
  chart      = "jaeger-operator"
  namespace  = "observability"
}
