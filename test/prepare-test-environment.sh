# #########################
# Set environment variables
#
# Generate JSON keyfiles for each GCP project and place them into:
# * Compute project -     gcp-gke/compute.json
# * Shared VPC project -  gcp-gke/vpc.json
# #########################

export GOOGLE_PROJECT="test-terraform-project-compute"
export TF_VAR_shared_vpc_host_google_project="test-terraform-shared-vpc"

if ls ../gcp-gke/compute.json; then
  export GOOGLE_CREDENTIALS=$(cat ../gcp-gke/compute.json)
  export TF_VAR_google_credentials=$(cat ../gcp-gke/compute.json)
fi

if ls ../gcp-gke/vpc.json; then
  export TF_VAR_shared_vpc_host_google_credentials=$(cat ../gcp-gke/vpc.json)
fi

# #############################
# Download and install pre-reqs
# #############################

# Github Runner - supports passwordless sudo
if command -v sudo; then
  sudo apt-get update
fi

# nektos/act - doesn't have sudo
if ! command -v sudo; then
  apt-get update
  apt-get install -y sudo
fi

if ! command -v kubectl; then
  # apt install -y apt-transport-https gnupg2 curl
  # curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  # apt install -y kubectl
  sudo apt-get install -y apt-transport-https gnupg2 curl
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
  echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee -a /etc/apt/sources.list.d/kubernetes.list
  sudo apt-get update
  sudo apt-get install -y kubectl
fi

if ! command -v git; then
  apt-get install -y git
fi

if ! command -v go; then
  cd /tmp || mkdir /tmp && cd /tmp
  wget -O go.tgz https://dl.google.com/go/go1.16.2.linux-amd64.tar.gz
  tar -C /usr/local -xvf go.tgz
  export PATH="/usr/local/go/bin:$PATH"
  export GOPATH=/opt/go/
  export PATH=$PATH:$GOPATH/bin
fi

if ! command -v unzip; then
 apt-get install -y unzip
fi

if ! command -v terraform; then
  curl -O https://releases.hashicorp.com/terraform/0.14.8/terraform_0.14.8_linux_amd64.zip
  unzip terraform_0.14.8_linux_amd64.zip
  mv terraform /usr/bin
  terraform version || return
fi

if ! command -v gcc; then
  apt-get install -y gcc
fi

if ! command -v python; then
  apt-get install -y python
fi

if ! ls ~/.kube; then
  mkdir ~/.kube
  echo "created .kube"
fi

if ! ls ~/.kube/config; then
  touch ~/.kube/config
  echo "created config in .kube"
fi

if ! command -v gcloud; then
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  sudo apt-get install apt-transport-https ca-certificates gnupg
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
  apt-get update && apt-get install -y google-cloud-sdk
fi
