# Post Provisioning

This section walks us through steps that need to get performed after the cluster has been provisioned. These steps can easily be automated as part of a pipeline, but are explicitly pulled out here for visibility.

## Enable AKS Cost Analysis

We will cover the topic of cost governance in Day 2. As it requires enabling add-on in Day 1 to populate the data, we will enable the add-on now. 

```bash
az feature register --namespace "Microsoft.ContainerService" --name "ClusterCostAnalysis"
az feature show --namespace "Microsoft.ContainerService" --name "ClusterCostAnalysis"
az provider register --namespace Microsoft.ContainerService
az aks update --name ${PREFIX}-aks --resource-group ${PREFIX}-rg --enable-cost-analysis
```




## Find Public IP of AKS api-server Endpoint

This section shows how to find the Public IP (PIP) of the AKS cluster to be able to add it to firewalls for IP whitelisting purposes.

```bash
# Get API-Server IP
kubectl get endpoints --namespace default kubernetes
```

## Find Public IP of Azure Application Gateway used for WAF

This section shows how to find the Public IP Address of the Azure Application Gateway which is used as a WAF, and the Ingress point for workloads into the Cluster.

```bash
# Retrieve the Public IP Address of the App Gateway.
az network public-ip show -g $RG -n $AGPUBLICIP_NAME --query "ipAddress" -o tsv
```

## Test Cluster Post Provisioning

This is a quick test to make sure that Pods can be created, and the Ingress Controller default backend is set up correctly.

- First we need to grab AKS cluster credentials, so we can access the api-server endpoint and run some commands.
- Second we will do a quick check via get nodes.
- Lastly, we will spin up a Pod, exec into it, and test our F/W rules.

```bash
# List out AKS Cluster(s) in a Table
az aks list -o table
# Get Cluster Admin Credentials
az aks get-credentials -g $RG -n $PREFIX-aks --admin
# Check Nodes
kubectl get nodes
# Test via a Pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: centos
spec:
  containers:
  - name: centos
    image: centos
    ports:
    - containerPort: 80
    command:
    - sleep
    - "3600"
EOF
# Check if Pod is Running
kubectl get po -o wide
# Once Pod is Running exec into the Pod
kubectl exec -it centos -- /bin/bash
# Inside of the Pod test the Ingress Controller Endpoint
curl 100.64.2.4
# This should be blocked by F/W
curl www.superman.com
# Exit out of Pod
exit
```




## Kubernetes Audit Logs

There is an overwhelming need for organizations to capture all data that they can in case they need it. The Kubernetes audit logs fall into this bucket. It produces a ton of data that chews up storage, and most organizations are not sure what to do with.

So what do we do? We highly encourage organizations to only capture the data that they need to help reduce costs as well as optimize around analytics that need to be done. The fewer data that needs to be processed, the less compute that is needed, which means less cost. So, do you really need the audit logs?

Ok, you get it, or you don't buy into selectively capturing data. Your organization needs to capture all the data because you don't know what you don't know.

### Capturing & Storing AKS Audit Logs

So how do I capture those Kubernetes audit logs and where should they be put? Directing the logs to Azure Monitor for Containers gets really expensive, really fast, due to the sheer volume of data records that are captured. Considering that most organizations are not 100% sure if they need the logs or not, and to keep costs to a minimum, the guidance is to direct the audit logs to Azure Storage.

- Click [Enable Kubernetes Logs](https://docs.microsoft.com/en-us/azure/aks/view-master-logs) for more details and direct **kube-audit** logs to an Azure Storage Account, **NOT Log Analytics**.

## Next Steps

[Deploy App](/deploy-app/README.md)

## Key Links

- [Enable Kubernetes Logs](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-log-query#resource-logs)
- [Azure Traffic Analytics](https://docs.microsoft.com/en-us/azure/network-watcher/traffic-analytics)

