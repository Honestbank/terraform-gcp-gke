### Use this file to override variables in the template
### Examples are provided below:

### Full GCP project name
google_project = "test-terraform-project-compute"

### GCP region
google_region = "asia-southeast2"

### Environment - can be ["test", "dev", "qa", "preprod", "prod"]
stage = "test"

### Friendly name for the cluster
cluster_purpose = "template"

### For use cases involving multiple clusters with the same purpose/environment
cluster_number = 01

### Cluster configuration values
# maximum_node_count           = 5 // Maximum 5 nodes per zone = 15 nodes
# cluster_service_account_name = "test-terraform-service-acc-636@test-terraform-project-01.iam.gserviceaccount.com"
