# Terraform Local-Backend Module for GCP (Google Cloud Platform) GKE (Google Kubernetes Engine) Build

Since Terratest doesn't yet support specifying a backend config file via command-line arguments,
this internal/external module structure is required to enable E2E testing using Terratest.

This folder can be init'ed and applied using Terraform to test functionality.

To run E2E tests, navigate to the [test folder](../test) and run `go test -v -timeout 30m`.

## Variables

| Variable | Description | Required | Default |
| -------- | ----------- | -------- | ------- |
| project | GCP project to use | yes | `test-terraform-project-01` |
| google_credentials | Contents of a GCP service account JSON keyfile, use `export TF_VAR_google_credentials=cat $(FILENAME)` | yes | none |
| region | GCP region to use | yes | `asia-southeast`2 |
| stage | Stage (aka Environment) - [test, dev, prod...] used as a prefix for all resources | yes | `test` |
| cluster_purpose | Purpose of this infrastructure - will be added to all resource names | yes | `tf-gke-templat`e |
| cluster_number | A 'count' variable to be appended to all resources | yes | `00` |
| zones | Zones (within a GCP region) to be used | yes | `["asia-southeast2-a", "asia-southeast2-b", "asia-southeast2-c"]` - all zones |
| release_channel | For clusters not using a static version, specify the release channel (RAPID, REGULAR, STABLE) | yes | `RAPID` |
| minimum_node_count | Minimum nodes per-zone | yes | `1` |
| maximum_node_count | Maximum nodes per-zone | yes | `2` |
| initial_node_count | Initial number of nodes per-zone (should equal minimum_node_count for faster builds) | yes | `1` |
| machine_type | Machine types to use for the GKE cluster | yes | `n1-standard-2` |
