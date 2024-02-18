# Cluster Provisioning

This lab walks you through provisioning a secure AKS cluster utilizing Terraform.  You may ask "Why not utilize Azure Resource Manager Templates?"... The reason we have utilized Terraform is that it gives a multi-platform provisioning tool, that also lets us automate the provisioning of non-Azure resources, so we'll have a full production cluster setup from a single provisioning tool.

Let's first create a fork of the sg-aks-workshop repo in our own GitHub account.

![Fork](./img/fork.png)

After forking the repo you'll need to clone it locally.

```bash
git clone https://github.com/<user_name>/sg-aks-workshop
```

Now change directories to the cluster-provisioning/terraform directory.

```bash
cd sg-aks-workshop/cluster-provisioning/terraform/aks/
```

We will also need to set up all our variables from the last lab, so we can utilize the networking infrastructure that was set up.

```bash
export TF_VAR_prefix=$PREFIX
export TF_VAR_resource_group=$RG
export TF_VAR_location=$LOCATION

export TF_VAR_azure_subnet_id=$(az network vnet subnet show -g $RG --vnet-name $VNET_NAME --name $AKSSUBNET_NAME --query id -o tsv)
export TF_VAR_azure_aag_subnet_id=$(az network vnet subnet show -g $RG --vnet-name $VNET_NAME --name $APPGWSUBNET_NAME --query id -o tsv)
export TF_VAR_azure_subnet_name=$APPGWSUBNET_NAME
export TF_VAR_azure_aag_name=$AGNAME
export TF_VAR_azure_aag_public_ip=$(az network public-ip show -g $RG -n $AGPUBLICIP_NAME --query id -o tsv)
export TF_VAR_azure_vnet_name=$VNET_NAME
export TF_VAR_github_organization=Azure # PLEASE NOTE: This should be your github username if you forked the repository.
export TF_VAR_github_token=<use previously created PAT token>
```

Now that we have all of our variables stored we can initialize Terraform. 

```bash
terraform init
```

This command is used to initialize a working directory containing Terraform configuration files. This is the first command that should be run after writing a new Terraform configuration or cloning an existing one from version control. It is safe to run this command multiple times.

Now that we have initialized our Terraform directory, we will want to run a `terraform plan`. The `terraform plan` command is a convenient way to check whether the execution plan for a set of changes matches your expectations without making any changes to real resources or to the state. For example, terraform plan might be run before committing a change to version control, to create confidence that it will behave as expected.

```bash
terraform plan
```

After running this command you'll see output like the following that will show what is going to be provisioned.

```bash
  # azurerm_container_registry.acr will be created
  + resource "azurerm_container_registry" "acr" {
...
  # azurerm_kubernetes_cluster.demo will be created
  + resource "azurerm_kubernetes_cluster" "demo" {
...
  # azurerm_log_analytics_solution.demo will be created
  + resource "azurerm_log_analytics_solution" "demo" {
...
  # azurerm_log_analytics_workspace.demo will be created
  + resource "azurerm_log_analytics_workspace" "demo" {
...
   # azurerm_role_assignment.example will be created
  + resource "azurerm_role_assignment" "example" {
...
  # azurerm_role_assignment.role1 will be created
  + resource "azurerm_role_assignment" "role1" {
...  

Plan: 6 to add, 0 to change, 0 to destroy.
```

Looking at the output, you can see that we are going to provision an Azure Container Registry, an Azure Kubernetes Service Cluster, and a Log Analytics Workspace. We will enable ContainerInsights on the Log Analytics Workspace to collect logs from the AKS cluster. We assign two roles to the AKS cluster, one for attaching ACR to AKS cluster and another for allowing AKS to create LoadBalancer type Service by giving "Network Contributor" to the managed identity of the AKS cluster.

Now that we have verified what will be deployed, we can execute the `terraform apply` command, which will provision all our resources to Azure.

```bash
terraform apply
```

**_This will take approximately 5-10 minutes to fully provision all of our resources_**

In the next section, we will talk about our approach to automating the setup, that is typically done in a post-install setup. We utilize Flux, which will automatically sync our Kubernetes manifest from a GitHub repo.

## GitOps and Ingress Controller Preparation

Before we move on to tne next chapter, we need to do two things quickly.

```bash
kubectl apply -f cert.yml
kubectl apply -f k8s.yml
```

## Enable Ingress Controller and App Gateway

Running Kubernetes in production requires a lot of additional features to be enabled such as Ingress Controllers, Service Meshes, Image Eraser, etc. AKS as a managed Kubernetes service from Azure provides a lot of these features out of the box under the name of add-ons. One of the add-ons is Web Application Routing, which is a Kubernetes ingress controller that is based on nginx ingress controller. This add-on is useful for managing traffic to your applications, providing SSL termination, and other L7 features.

```bash

az aks get-credentials --resource-group ${PREFIX}-rg --name ${PREFIX}-aks --admin
The behavior of this command has been altered by the following extension: aks-preview
Merged "${PREFIX}-aks-admin" as current context in /Users/jaylee/.kube/config

az aks approuting enable --resource-group ${PREFIX}-rg --name ${PREFIX}-aks

kubectl get ingressclasses
NAME                                 CONTROLLER                                 PARAMETERS   AGE
webapprouting.kubernetes.azure.com   webapprouting.kubernetes.azure.com/nginx   <none>       2m42s

```

By default, application routing add-on creates a public IP address for the ingress controller. You can find the public IP address of the ingress controller by running the following command:

```bash
kubectl get service  -n app-routing-system
NAME               TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                                      AGE
nginx              LoadBalancer   192.168.8.160    20.197.69.173   80:30674/TCP,443:31854/TCP,10254:30089/TCP   6m48s
``` 

We will create a new service to use the internal IP address of the ingress controller. This will allow us to use the internal IP address of the ingress controller so that we can use it to connect with the Application Gateway. There is a file "nginx-internal.yml" which create a new internal Load Balancer in the ILBSUBNET. 

```bash
kubectl apply -f nginx-internal.yml
kubectl get service -n app-routing-system
NAME               TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                                      AGE
nginx              LoadBalancer   192.168.8.160    20.197.69.173   80:30674/TCP,443:31854/TCP,10254:30089/TCP   6m48s
nginx-internal-0   LoadBalancer   192.168.185.35   100.64.2.4      80:31229/TCP,443:32394/TCP,10254:30329/TCP   37s

```

We will again use Terraform to create an Application Gateway and configure it to use the internal IP address of the ingress controller. 

```bash
cd sg-aks-workshop/cluster-provisioning/terraform/appgw
```

In "aag.tf" file, there are ip addresses that should be changed to the internal IP address of the ingress controller, backend_address_pool and probe. 

```bash
terraform init
terraform plan
terraform apply
```

---
**NOTE**
If you face the issue regarding NSG, create a new rule to allow traffic to the Application Gateway. 

```bash
Error: creating Application Gateway: (Name "sg-appgateway" / Resource Group "jayaksworkshop-rg"): network.ApplicationGatewaysClient#CreateOrUpdate: Failure sending request: StatusCode=400 -- Original Error: Code="ApplicationGatewaySubnetInboundTrafficBlockedByNetworkSecurityGroup" Message="Network security group /subscriptions/6535fca9-4fa4-43ee-9320-b2f34de09589/resourceGroups/jayaksworkshop-rg/providers/Microsoft.Network/networkSecurityGroups/jayaksworkshop-vnet-jayaksworkshop-appgwsubnet-nsg-southeastasia blocks incoming internet traffic on ports 65200 - 65535 to subnet /subscriptions/6535fca9-4fa4-43ee-9320-b2f34de09589/resourceGroups/jayaksworkshop-rg/providers/Microsoft.Network/virtualNetworks/jayaksworkshop-vnet/subnets/jayaksworkshop-appgwsubnet, associated with Application Gateway /subscriptions/6535fca9-4fa4-43ee-9320-b2f34de09589/resourceGroups/jayaksworkshop-rg/providers/Microsoft.Network/applicationGateways/sg-appgateway. This is not permitted for Application Gateways that have V2 Sku." Details=[]
```
This is an example of the command to create a new rule to allow traffic to the Application Gateway. 

```bash
az network nsg rule create -g jayaksworkshop-rg --nsg-name jayaksworkshop-vnet-jayaksworkshop-appgwsubnet-nsg-southeastasia -n GatewayManager --priority 4096 --source-port-range '*' --access allow --destination-port-ranges 65200-65535 --source-address-prefixes GatewayManager --protocol Tcp
```

## GitOps Approach To Managing Clusters

One of the most important aspects of managing a Kubernetes cluster is the ability to manage the configuration of the cluster. This includes the ability to manage the configuration of the cluster, the applications running on the cluster, and the ability to manage the configuration of the cluster itself. This is where GitOps comes in.

> Why use a GitOps approach? Adopting GitOps in your CI/CD pipelines increases the security of your application and systems. With GitOps, a reconciliation operator is installed into the cluster itself that acts based on the configuration in a git repo that uses separate credentials. The operator reconciles the desired state as expressed in the manifest files, stored in the git repo, against the actual state of the cluster. This means that credentials and other secrets don’t ever leave the cluster. This also means that continuous integration operates independently, rather than on the cluster directly and that each pipeline component needs only a single read-write credential. Since cluster credentials never leave the cluster, your secrets are kept close. -WeaveWorks

Pull Requests enabled on the config repo are independent of the cluster itself and can be reviewed by developers. This leaves a complete audit trail of every tag update and config change, regardless of whether it was made manually or automatically. Although using git as part of your CI/CD pipeline adds another layer of defense, it also means that the security onus is shifted to git itself.

Flux was one of the first tools to enable the GitOps approach, and it’s the
tool we will use due to its maturity and level of adoption. Below is a diagram that describes how the approach works.

![GitOps Diagram](./img/gitops.png "GitOps Diagram")


[Tutorial: Deploy applications using GitOps with Flux v2](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/tutorial-use-gitops-flux2?tabs=azure-cli) has a great tutorial on how to use GitOps with Flux v2. And here is the simple guide to get you started.

**CHALLENGE** - GitOps requres the F/W rule to allow the traffic to '$LOCATION.dp.kubernetesconfiguration.azure.com. Instructor will give you the guidance.

```bash
## Regsiter the following Azure resource providers
az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.KubernetesConfiguration

## Enable CLI Extension
az extension add -n k8s-configuration
az extension add -n k8s-extension

## Create a Flux configuration - Change the values to match your environment

az k8s-configuration flux create -g $PREFIX-rg -c $PREFIX-aks -n cluster-config --namespace default -t managedClusters --scope cluster -u https://github.com/{github_account}/sg-aks-workshop --branch master --kustomization name=infra path=./cluster-config prune=true --interval 1m
```

You'll notice once your flux configuration is provisioned, you'll have the following deployed:

- **Namespaces** - Three namespaces will be created, `dev`, `staging`, and `production`. These namespaces will be used to deploy your applications to the cluster.

- **Network Policy Rules** - The network policies will restrict communication between different teams' namespace, to limit the exposure of access between namespaces.

- **LimitRanges** - LimitRanges will allow you to set resource consumption governance per namespaces to limit the amount of resources a team or user can deploy to a cluster.
- 
- **Quotas** - Quotas will allow you to set resource consumption governance on a namespace to limit the amount of resources a team or user can deploy to a cluster. It gives you a way to logically carve out resources of a single cluster.

The below diagram shows our production cluster

![Prod Diagram](img/app_after.png "Prod Cluster")

## Next Steps

[Post Provisioning](/cluster-post-provisioning/README.md)

## Key Links

- Flux Docs - <https://docs.fluxcd.io/en/stable/>
- Terraform AKS Docs - <https://www.terraform.io/docs/providers/azurerm/r/kubernetes_cluster.html>