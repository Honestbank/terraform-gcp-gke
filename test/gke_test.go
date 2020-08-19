package test

import (
	"github.com/gruntwork-io/terratest/modules/shell"
	v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"log"
	"os"
	"path/filepath"
	"testing"

	"github.com/gruntwork-io/terratest/modules/gcp"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTerraformGcpGkeTemplate(t *testing.T) {

	testCaseName := "gke_test"
	// Create all resources in the following zone
	gcpIndonesiaRegion := "asia-southeast2"

	t.Run(testCaseName, func(t *testing.T) {
		t.Parallel()

		// Create a directory path that won't conflict
		workingDir := filepath.Join(".", "test-runs", testCaseName)

		test_structure.RunTestStage(t, "create_test_copy", func() {
			testFolder := test_structure.CopyTerraformFolderToTemp(t, "../gcp-gke", ".")
			logger.Logf(t, "path to test folder %s\n", testFolder)
			test_structure.SaveString(t, workingDir, "gkeClusterTerraformModulePath", testFolder)
		})

		test_structure.RunTestStage(t, "create_terratest_options", func() {
			gkeClusterTerraformModulePath := test_structure.LoadString(t, workingDir, "gkeClusterTerraformModulePath")
			tmpKubeConfigPath := k8s.CopyHomeKubeConfigToTemp(t)
			kubectlOptions := k8s.NewKubectlOptions("", tmpKubeConfigPath, "kube-system")
			uniqueID := random.UniqueId()

			// make sure to `export` one of these vars
			// GOOGLE_PROJECT GOOGLE_CLOUD_PROJECT GOOGLE_CLOUD_PROJECT_ID
			// GCLOUD_PROJECT CLOUDSDK_CORE_PROJECT
			project := gcp.GetGoogleProjectIDFromEnvVar(t)
			credentials := gcp.GetGoogleCredentialsFromEnvVar(t)
			region := gcpIndonesiaRegion
			gkeClusterTerratestOptions := createTestGKEClusterTerraformOptions(
				project,
				region,
				credentials,
				gkeClusterTerraformModulePath)

			// if testCase.overrideDefaultSA {
			// 	gkeClusterTerratestOptions.Vars["override_default_node_pool_service_account"] = "1"
			// }

			logger.Logf(t,"gkeClusterTerratestOptions: %v\n", gkeClusterTerratestOptions)
			test_structure.SaveString(t, workingDir, "uniqueID", uniqueID)
			test_structure.SaveString(t, workingDir, "project", project)
			test_structure.SaveString(t, workingDir, "region", region)
			test_structure.SaveTerraformOptions(t, workingDir, gkeClusterTerratestOptions)
			test_structure.SaveKubectlOptions(t, workingDir, kubectlOptions)
		})

		defer test_structure.RunTestStage(t, "cleanup", func() {
			gkeClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
			terraform.Destroy(t, gkeClusterTerratestOptions)

			kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
			err := os.Remove(kubectlOptions.ConfigPath)
			require.NoError(t, err)
		})

		log.Printf("About to start terraform_apply")
		test_structure.RunTestStage(t, "terraform_apply", func() {
			gkeClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
			terraform.InitAndApply(t, gkeClusterTerratestOptions)
		})

		logger.Log(t, "About to start configure_kubectl")
		test_structure.RunTestStage(t, "configure_kubectl", func() {
			gkeClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)

			logger.Logf(t,"gkeClusterTerratestOptions looks like: %v", gkeClusterTerratestOptions)

			kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
			logger.Log(t, "got kubectlOptions")

			project := test_structure.LoadString(t, workingDir, "project")
			logger.Log(t, "got project = " +  project)

			region := test_structure.LoadString(t, workingDir, "region")
			logger.Log(t, "got region = " +  region)

			clusterName, clusterNameErr := terraform.OutputE(t, gkeClusterTerratestOptions, "cluster_name")
			if clusterNameErr != nil {
				logger.Log(t, "Error getting cluster_name from 'terraform output cluster_name': %v", clusterNameErr)
			} else {
				logger.Log(t, "got clusterName = %s", clusterName)
			}

			cmd := shell.Command{
				Command: "gcloud",
				Args: []string{
					"container",
					"clusters",
					"get-credentials", clusterName,
					"--region", region,
					"--project", project,
					"--quiet",
				},
				Env: map[string]string{
					"KUBECONFIG": kubectlOptions.ConfigPath,
				},
			}
			shell.RunCommand(t, cmd)
		})

		logger.Log(t,"About to start wait_for_workers")
		test_structure.RunTestStage(t, "wait_for_workers", func() {
			kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
			verifyGkeNodesAreReady(t, kubectlOptions)
		})

		logger.Log(t, "About to start terraform_verify_plan_noop")
		test_structure.RunTestStage(t, "terraform_verify_plan_noop", func() {
			gkeClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
			planResult := terraform.InitAndPlan(t, gkeClusterTerratestOptions)
			resourceCount := terraform.GetResourceCount(t, planResult)
			assert.Equal(t, 0, resourceCount.Change)

			// There are 4 always-run steps
			// 1 - download_kubectl
			// 2 - setup_gcloud_cli
			// 3 - configure_kubectl
			// 4 - install_cert-manager_crds
			assert.Equal(t, 4, resourceCount.Add)
			assert.Equal(t, 4, resourceCount.Destroy)
			assert.Contains(t, planResult, "setup_gcloud_cli")
			assert.Contains(t, planResult, "configure_kubectl")
			assert.Contains(t, planResult, "download_kubectl")
		})

		logger.Log(t, "About to start verify_istio`")
		test_structure.RunTestStage(t, "verify_istio", func() {
			kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)

			_, istioOperatorNamespaceError := k8s.GetNamespaceE(t, kubectlOptions, "istio-operator")
			assert.Nil(t, istioOperatorNamespaceError, "Could not find istio-operator namespace")

			_, istioSystemNamespaceError := k8s.GetNamespaceE(t, kubectlOptions, "istio-system")
			assert.Nil(t, istioSystemNamespaceError, "Could not find istio-system namespace")

			kubectlOptions.Namespace = "istio-system"
			istioPods, getIstioPodsError := k8s.ListPodsE(t, kubectlOptions, v1.ListOptions{})
			assert.Nil(t, getIstioPodsError, "error getting Istio pods")
			assert.Greater(t, len(istioPods), 0, "no Pods present in istio-system namespace")
		})

		test_structure.RunTestStage(t, "verify cert-manager", func() {
			kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)

			_, certManagerNamespaceError := k8s.GetNamespaceE(t, kubectlOptions, "cert-manager")
			assert.Nil(t, certManagerNamespaceError, "Could not find cert-manager namespace")

			certManagerPods, certManagerPodsError := k8s.ListPodsE(t, kubectlOptions, v1.ListOptions{})
			assert.Nil(t, certManagerPodsError, "Could not get pods from cert-manager namespace")
			assert.Greater(t, len(certManagerPods), 0, "No pods present in cert-manager namespace")
		})
	})
}
