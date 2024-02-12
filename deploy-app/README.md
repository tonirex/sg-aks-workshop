# Deploy App

This section walks us through deploying the sample application on AKS. While deploying an app, 

## Web and Worker Image Classification Services

This is a simple SignalR application with two parts. The web front-end is a .NET Core MVC application that serves up a single page that receives messages from the SignalR Hub and displays the results. The back-end worker application retrieves data from Azure Files and processes the image using a TensorFlow model and sends the results to the SignalR Hub on the front-end.

The end result on the front-end should display what type of fruit image was processed by the Tensorflow model. And because it is SignalR there is no browser refreshing needed.

## Container Development

Before we get into setting up the application, let's have a quick discussion on what container development looks like for the customer. No development environment is the same as it is not a one size fits all when it comes to doing development. Computers, OS, languages, and IDEs to name a few things are hardly ever the same configuration/setup. And if you throw the developer themselves in that mix it is definitely not the same.

As a result, different users work in different ways. The following are just a few of the **inner DevOps loop** tools that we are seeing in this eco-system, feel free to try any of them out and let us know what you think. And if it hits the mark.

### Tilt

Tilt is a CLI tool used for local continuous development of microservice applications. Tilt watches your files for edits with tilt-up, and then automatically builds, pushes, and deploys any changes to bring your environment up-to-date in real-time. Tilt provides visibility into your microservices with a command-line UI. In addition to monitoring deployment success, the UI also shows logs and other helpful information about your deployments.

Click [here](https://github.com/windmilleng/tilt) for more details and to try it out.

### Telepresence

Telepresence is an open-source tool that lets you run a single service locally, while connecting that service to a remote Kubernetes cluster. This lets developers working on multi-service applications to:

1. Do fast local development of a single service, even if that service depends on other services in your cluster. Make a change to your service, save, and you can immediately see the new service in action.
2. Use any tool installed locally to test/debug/edit your service. For example, you can use a debugger or IDE!
3. Make your local development machine operate as if it's part of your Kubernetes cluster. If you've got an application on your machine that you want to run against a service in the cluster -- it's easy to do.

Click [here](https://www.telepresence.io/reference/install) for more details and to try it out.

## Push Images to Azure Container Registry (ACR)

This section grabs the container images from Docker Hub and then pushes them to the Azure Container Registry that was created.

```bash
# Pull Images from Docker Hub to Local Workstation
docker pull kevingbb/imageclassifierweb:v1
docker pull kevingbb/imageclassifierworker:v1

# Authenticate to ACR
az acr list -o table
az acr login -n ${PREFIX}acr

# Push Images to ACR
docker tag kevingbb/imageclassifierweb:v1 ${PREFIX}acr.azurecr.io/imageclassifierweb:v1
docker tag kevingbb/imageclassifierworker:v1 ${PREFIX}acr.azurecr.io/imageclassifierworker:v1
docker push ${PREFIX}acr.azurecr.io/imageclassifierweb:v1
docker push ${PREFIX}acr.azurecr.io/imageclassifierworker:v1
```

## Deploy Application

There is an app.yaml file in this directory so either change into this directory or copy the contents of the file to a filename of your choice. Once you have completed the previous step, apply the manifest file and you will get the web and worker services deployed into the **dev** namespace.

```bash
# Deploy the Application Resources
kubectl apply -f app.yaml
# Display the Application Resources
kubectl get deploy,rs,po,svc,ingress -n dev
```

### File Share Setup

You will notice that some of the pods are not starting up, this is because an Azure File Share is missing and the secret to access Azure Files.

Create an Azure Storage account in your resource group.

```bash
# declare the share referenced above.
SHARE_NAME=fruit

# az storage creation for app.
STORAGE_ACCOUNT=${PREFIX}storage

# create storage account
az storage account create -g $RG -n $STORAGE_ACCOUNT

# create an azure files share to contain fruit images
az storage share create --name $SHARE_NAME --account-name $STORAGE_ACCOUNT

# get the key
STORAGE_KEY=$(az storage account keys list -g $RG -n $STORAGE_ACCOUNT --query "[0].value" | tr -d '"')

# create a secret
kubectl create secret generic fruit-secret \
  --from-literal=azurestorageaccountname=$STORAGE_ACCOUNT \
  --from-literal=azurestorageaccountkey=$STORAGE_KEY \
  -n dev
```

From the Azure portal upload all the contents of the ./deploy-app/fruit/ directory.
![Upload fruit directory](/deploy-app/img/upload_images.png)

```bash
# Check to see Worker Pod is now Running
kubectl get deploy,rs,po,svc,ingress,secrets -n dev
```

The end result will look something like this.

![Dev Namespace Output](/deploy-app/img/app_dev_namespace.png)

## Test out Application Endpoint

This section will show you how to test and see if the application endpoint is up and running.

```bash
# Exec into Pod and Test Endpoint
kubectl run -i --tty ubuntu --image=ubuntu:22.04 --restart=Never -- /bin/bash
apt update
apt install curl
# Inside of the Pod test the Ingress Controller Endpoint (Tensorflow in the page Title)
curl -sSk 100.64.2.4 | grep -i 'TensorFlow'
# You should have seen the contents of an HTML file dumped out. If not, you will need to troubleshoot.
# Exit out of Pod
exit
```

- Now Test with the WAF Ingress Point

```bash
az network public-ip show -g $RG -n $AGPUBLICIP_NAME --query "ipAddress" -o tsv
```

## Adding in Secrets Mgmt

This section will take a look at the same application, but add in some more capabilities and storing the sensitive information to turn on those capabilities securely.

Here is a small list of things that will be added:

- Health Checks via Liveness and Readiness Probes.
- Application Instrumentation with Instrumentation Key securely stored in Azure Key Vault (AKV).
- Add a Title to the App with that Title stored in AKV for illustration purposes only.

When dealing with secrets we typically need to store some type of bootstrapping credential(s) or connection string to be able to access the secure store.

**What if there was another way?**

There is, it is called AAD Pod Identity, or Managed Pod Identity. We are going to assign an Azure Active Directory Identity to a running Pod which will automatically grab an Azure AD backed Token which we can then use to securely access Azure Key Vault.

**Pretty Cool!**

### Create Azure Key Vault (AKV) & Secrets

- In this section we will create the secrets backing store which will be Azure Key Vault and populate it with the secrets information.

```bash
# Create Azure Key Vault Instance
az keyvault create -g $RG -n ${PREFIX}akv -l $LOC --enabled-for-template-deployment true
# Retrieve Application Insights Instrumentation Key
az resource show \
    --resource-group $RG \
    --resource-type "Microsoft.Insights/components" \
    --name ${PREFIX}-ai \
    --query "properties.InstrumentationKey" -o tsv
INSTRUMENTATION_KEY=$(az resource show -g $RG --resource-type "Microsoft.Insights/components" --name ${PREFIX}-ai --query "properties.InstrumentationKey" -o tsv)
# Populate AKV Secrets
az keyvault secret set --vault-name ${PREFIX}akv --name "AppSecret" --value "MySecret"
az keyvault secret show --name "AppSecret" --vault-name ${PREFIX}akv
az keyvault secret set --vault-name ${PREFIX}akv --name "AppInsightsInstrumentationKey" --value $INSTRUMENTATION_KEY
az keyvault secret show --name "AppInsightsInstrumentationKey" --vault-name ${PREFIX}akv
```

### Create Azure AD Identity

- Now that we have AKV and the secrets setup, we need to create the Azure AD Identity and permissions to AKV.

```bash
# Enable AAD Pod Identity
az aks update -g $RG -n $PREFIX-aks --enable-pod-identity

# Create Azure AD Identity
export AAD_IDENTITY=${PREFIX}identity
az identity create -g $RG -n $AAD_IDENTITY -o json
# Sample Output
{
  "clientId": "CLIENTID",
  "clientSecretUrl": "https://control-eastus.identity.azure.net/subscriptions/SUBSCRIPTION_ID/resourcegroups/contosofin-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/contosofinidentity/credentials?tid=TID&aid=AID",
  "id": "/subscriptions/SUBSCRIPTION_ID/resourcegroups/contosofin-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/contosofinidentity",
  "location": "eastus",
  "name": "jayaiaidentity",
  "principalId": "PRINCIPALID",
  "resourceGroup": "jayaia-rg",
  "tags": {},
  "tenantId": "TENANT_ID",
  "type": "Microsoft.ManagedIdentity/userAssignedIdentities"
}
# Grab PrincipalID & ClientID & TenantID from Above
export AAD_IDENTITY_PRINCIPALID=$(az identity show -g $RG -n $AAD_IDENTITY --query "principalId" -o tsv)
```

- Now that we have the Azure AD Identity setup, the next step is to set up the access policy (RBAC) in AKV to allow or deny certain permissions to the data.

```bash
# Setup Access Policy (Permissions) in AKV
az keyvault set-policy \
    --name ${PREFIX}akv \
    --secret-permissions list get \
    --object-id $AAD_IDENTITY_PRINCIPALID
```

### Create Azure AD Identity Resources in AKS

- Now that we have all the Azure AD Identity and AKS Cluster SP permissions setup. The next step is to setup and configure the AAD Pod Identities in AKS.

```bash

export AAD_IDENTITY_RESOURCE_ID="$(az identity show -g ${RG} -n ${IDENTITY_NAME} --query id -otsv)"

az aks pod-identity add --resource-group ${RG} --cluster-name ${PREFIX}-aks --namespace dev --name akv-identity --identity-resource-id ${AAD_IDENTITY_RESOURCE_ID}

# Take a look at AAD Resources
kubectl get azureidentity,azureidentitybinding -n dev
```

### Deploy Updated Version of Application which accesses AKV

- Now that the bindings are set up, we are ready to test it out by deploying our application and see if it is able to read everything it needs from AKV.

**NOTE: It is the following label, configured via above, that determines whether or not the Identity Controller tries to assign an AzureIdentity to a specific Pod.**

metadata:
labels:
**aadpodidbinding: akv-identity**
name: my-pod

```bash
# Remove Existing Application
kubectl delete -f app.yaml

# Create Secret for Name of Azure Key Vault for App Bootstrapping
kubectl create secret generic image-akv-secret \
  --from-literal=KeyVault__Vault=${PREFIX}akv \
  -n dev

# Deploy v3 of the Application
kubectl apply -f appv3msi.yaml

# Display the Application Resources
kubectl get deploy,rs,po,svc,ingress,secrets -n dev
```

- Once the pods are up and running, check via the WAF Ingress Point

```bash
# Get Public IP Address of Azure App Gateway
az network public-ip show -g $RG -n $AGPUBLICIP_NAME --query "ipAddress" -o tsv
```

## Next Steps

[Cost Governance](/cost-governance/README.md)

## Key Links

- [Tilt](https://github.com/windmilleng/tilt)
- [Telepresence](https://telepresence.io)
- [Azure Dev Spaces](https://docs.microsoft.com/en-us/azure/dev-spaces/about)
