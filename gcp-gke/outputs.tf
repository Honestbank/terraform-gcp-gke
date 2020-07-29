/**
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

output "kubernetes_endpoint" {
  sensitive = true
  value     = module.primary_cluster_auth.host
}

output "client_token" {
  sensitive = true
  value     = module.primary_cluster_auth.token
}

output "ca_certificate" {
  value = module.primary_cluster_auth.cluster_ca_certificate
}

output "kubeconfig_raw" {
  value = module.primary_cluster_auth.kubeconfig_raw
}

output "service_account" {
  description = "The default service account used for running nodes."
  value       = module.primary-cluster.service_account
}

output "cluster_name" {
  description = "The GKE cluster name that was built"
  value       = module.primary-cluster.name
}

output "elastic_secret_password" {
  description = "Password from Elastic secret"
  value       = data.kubernetes_secret.elastic_password.data["elastic"]
}
