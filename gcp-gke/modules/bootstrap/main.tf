# setup_gcloud_cli steps
# 1 - write GCP credentials to file
# 2 - download gcloud CLI and extract
# 3 - activate the service account which means tell gcloud CLI to use these credentials
resource "null_resource" "setup_gcloud_cli" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOH
  cat <<< '${var.google_credentials}' > google_credentials_keyfile.json
  curl https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-302.0.0-linux-x86_64.tar.gz | tar xz
  ./google-cloud-sdk/bin/gcloud auth activate-service-account --key-file google_credentials_keyfile.json --quiet
  EOH

    interpreter = ["/bin/bash", "-c"]
  }
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
}

# get kubeconfig
resource "null_resource" "configure_kubectl" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOH
      ./google-cloud-sdk/bin/gcloud container clusters get-credentials "${var.cluster_name}" --region "${var.cluster_location}" --project "${var.google_project}" --quiet
EOH
  }

  depends_on = [null_resource.setup_gcloud_cli]
}

# Install Istio Operator using istioctl
resource "null_resource" "install_istio_operator" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOH
curl -sL https://istio.io/downloadIstioctl | sh -
export PATH=$PATH:$HOME/.istioctl/bin
istioctl operator init
kubectl label namespace default istio-injection=enabled --overwrite
EOH
  }

  depends_on = [null_resource.download_kubectl, null_resource.configure_kubectl]
}

# Set up Kiali credentials
resource "null_resource" "set_kiali_credentials" {
  triggers = {
    always_run = timestamp()
  }

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

  depends_on = [null_resource.download_kubectl, null_resource.configure_kubectl]
}

# Install IstioOperator resource manifest to trigger mesh installation
resource "null_resource" "install_IstioOperator_manifest" {
  triggers = {
    always_run = timestamp()
  }

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
    prometheus:
      enabled: false
    prometheusOperator:
      enabled: true
  values:
    prometheusOperator:
      createPrometheusResource: false
EOF
EOH
  }

  // These two dependencies implicitly add dependencies to null_resource.download_kubectl
  // and null_resource.configure_kubectl
  depends_on = [null_resource.install_istio_operator, null_resource.set_kiali_credentials]
}

# Install Elastic operator
resource "null_resource" "install_Elastic_operator" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOH
kubectl apply -f https://download.elastic.co/downloads/eck/1.2.0/all-in-one.yaml
EOH
  }

  depends_on = [null_resource.download_kubectl, null_resource.configure_kubectl]
}

# Install Elasticsearch and Kibana
resource "null_resource" "install_Elastic_resources" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOH
kubectl apply -f "${path.module}/elastic/elastic-basic-cluster.yaml"
kubectl apply -f "${path.module}/elastic/elastic-filebeat.yaml"
kubectl apply -f "${path.module}/elastic/elastic-kibana.yaml"
EOH
  }

  depends_on = [null_resource.install_Elastic_operator]
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
}

### cert-manager (v0.16.1)
# Install cert-manager CRDs
resource "null_resource" "install_cert-manager_crds" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOH
if ! command -v kubectl; then alias kubectl=./kubectl; fi;
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.16.1/cert-manager.crds.yaml
EOH
  }

  depends_on = [null_resource.configure_kubectl]
}

# Install cert-manager
resource "helm_release" "cert-manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "0.16.1"
  namespace        = "cert-manager"
  create_namespace = true

  depends_on = [null_resource.install_cert-manager_crds]
}
