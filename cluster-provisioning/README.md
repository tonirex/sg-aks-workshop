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
export TF_VAR_github_organization=Azure
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


## Enable Ingress Controller and App Gateway

Running Kubernetes in production requires a lot of additional features to be enabled such as Ingress Controllers, Service Meshes, Image Eraser, etc. AKS as a managed Kubernetes service from Azure provides a lot of these features out of the box under the name of add-ons. One of the add-ons is Web Application Routing, which is a Kubernetes ingress controller that is based on nginx ingress controller. This add-on is useful for managing traffic to your applications, providing SSL termination, and other L7 features.

```bash

az aks get-credentials --resource-group ${PREFIX}-rg --name ${PREFIX}-aks --admin
The behavior of this command has been altered by the following extension: aks-preview
Merged "${PREFIX}-aks-admin" as current context in /Users/xxx/.kube/config

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

We will create a new service to use the internal IP address of the ingress controller. This will allow us to use the internal IP address of the ingress controller so that we can use it to connect with the Application Gateway. There is a file "nginx-internal.yml" which create a new internal Load Balancer in the ILBSUBNET. Ensure to set the value of service.beta.kubernetes.io/azure-load-balancer-internal-subnet to your corresponding $PREFIX-ILBSubnet name.

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
az network nsg rule create -g $PREFIX-rg --nsg-name $PREFIX-vnet-jayaksworkshop-appgwsubnet-nsg-southeastasia -n GatewayManager --priority 4096 --source-port-range '*' --access allow --destination-port-ranges 65200-65535 --source-address-prefixes GatewayManager --protocol Tcp
```


The below diagram shows our production cluster

![Prod Diagram](img/app_after.png "Prod Cluster")

## Next Steps

[Post Provisioning](/cluster-post-provisioning/README.md)

## Key Links

- Flux Docs - <https://docs.fluxcd.io/en/stable/>
- Terraform AKS Docs - <https://www.terraform.io/docs/providers/azurerm/r/kubernetes_cluster.html>