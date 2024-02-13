# ETC
## Cluster Upgrade With Node Pools

With nodepools available in AKS, we can decouple the Control Plane upgrade from the nodes upgrade, and we will start by upgrading our control plane.

**Note** Before we start, at this stage you should:
1- Be fully capable of spinning up your cluster and restore your data in case of any failure (check the backup and restore section)
2- Know that control plane upgrades don't impact the application as its running on the nodes
3- You know that your risk is a failure on the Control Plane and in case this happened you should go and spin up a new cluster and migrate then open a support case to understand what went wrong.

```bash
az aks upgrade -n ${PREFIX}-aks -g $RG -k 1.15.7 --control-plane-only

Kubernetes may be unavailable during cluster upgrades.
Are you sure you want to perform this operation? (y/n): **y**
Since control-plane-only argument is specified, this will upgrade only the control plane to 1.14.8. Node pool will not change. Continue? (y/N): **y**
{
  "aadProfile": null,
  "addonProfiles": null,
  "agentPoolProfiles": [
    {
      "availabilityZones": null,
      "count": 1,
      "enableAutoScaling": null,
      "enableNodePublicIp": null,
      "maxCount": null,
      "maxPods": 110,
      "minCount": null,
      "name": "node1311",
      "nodeTaints": null,
      "orchestratorVersion": "1.14.7",
      "osDiskSizeGb": 100,
      "osType": "Linux",
      "provisioningState": "Succeeded",
      "scaleSetEvictionPolicy": null,
      "scaleSetPriority": null,
      "type": "VirtualMachineScaleSets",
      "vmSize": "Standard_DS2_v2",
      "vnetSubnetId": null
    }
  ],
  "apiServerAccessProfile": null,
  "dnsPrefix": "aks-nodepo-ignite-2db664",
  "enablePodSecurityPolicy": false,
  "enableRbac": true,
  "fqdn": "aks-nodepo-ignite-2db664-6e9c6763.hcp.eastus.azmk8s.io",
  "id": "/subscriptions/2db66428-abf9-440c-852f-641430aa8173/resourcegroups/ignite/providers/Microsoft.ContainerService/managedClusters/aks-nodepools-upgrade",
  "identity": null,
  "kubernetesVersion": "1.15.7",
 ....
```

**Note** The Control Plane can support N-2 kubelet on the nodes, which means 1.15 Control Plane supports 1.14, and 1.13 Kubelet. Kubelet can't be *newer* than the Control Plane. more information can be found [here](https://kubernetes.io/docs/setup/release/version-skew-policy/#kube-apiserver)

Let's add a new node pool with the desired version "1.15.7"

```bash
az aks nodepool add \
    --cluster-name ${PREFIX}-aks \
    --resource-group $RG \
    --name nodepoolblue \
    --node-count 4 \
    --node-vm-size Standard_DS3_v2 \
    --kubernetes-version 1.15.7

# Lets check our nodepools
kubectl get nodes
```

```bash
NAME                               STATUS   ROLES   AGE   VERSION
aks-node1311-64268756-vmss000000   Ready    agent   40m   v1.15.7
aks-node1418-64268756-vmss000000   Ready    agent   75s   v1.14.7
```

TEST TEST TEST, in whatever way you need to test to verify that your application will run on the new node pool, normally you will spin up a test version of your application; if things are in order then proceed to move workloads

Now we will need to taint the existing nodepool, so no new workloads are scheduled while we migrate workloads to the new nodepool.

```bash
kubectl taint node aks-agentpool-31778897-vmss000000 aks-agentpool-31778897-vmss000001 aks-agentpool-31778897-vmss000002 upgrade=true:NoSchedule
```

Now the nodes are tainted we can now drain each node to move the workloads over to the upgraded node pool.

```bash
kubectl drain aks-agentpool-31778897-vmss000000 --ignore-daemonsets --delete-local-data
```

**You will need to drain each node in the pool for all workloads to move over to the new nodepool.**

Check if the pods are running, note that all the new pods are in the new nodepool. You will see DameonSets we ignored still running on those initial nodes.

```bash
kubectl get pods -o wide
```

```bash
NAME                                     READY   STATUS    RESTARTS   AGE    IP             NODE                                   NOMINATED NODE   READINESS GATES
linkerd-controller-6d6cb84b49-f8kdc      3/3     Running   4          2m3s   100.64.1.205   aks-nodepoolblue-31778897-vmss000003   <none>           <none>
linkerd-destination-56487475c4-xtr8k     2/2     Running   2          2m4s   100.64.1.212   aks-nodepoolblue-31778897-vmss000003   <none>           <none>
linkerd-identity-64f89c776f-r6v46        2/2     Running   2          2m4s   100.64.1.102   aks-nodepoolblue-31778897-vmss000000   <none>           <none>
linkerd-proxy-injector-5956d6ffb-5h44l   2/2     Running   2          2m3s   100.64.1.197   aks-nodepoolblue-31778897-vmss000003   <none>           <none>
linkerd-sp-validator-747dcd685c-swsp9    2/2     Running   2          2m4s   100.64.1.218   aks-nodepoolblue-31778897-vmss000003   <none>           <none>
```



## Resource Management

One of the important task of day 2 operations is resource management. Resource Management consists of maintaining adequate resources to serve your workloads. Kubernetes provides built-in mechanisms to provide both soft and hard limits on CPU and Memory. It's important to understand how these request and limits work as it will ensure you provide adequate resource utilization for your cluster.

__Requests__ are what the container is guaranteed to get. If a container requests a resource then Kubernetes will only schedule it on a node that satisfies the request. __Limits__, on the other hand, ensure a container never goes above a certain configured value. The container is only allowed to go up to this limit, and then it is restricted.

When a container does hit the limit there is different behavior from when it hits a memory limit vs a CPU limit. With a memory limit the container will be killed and you'll see an "Out Of Memory Error". When a CPU limit is hit it will just start throttling the CPU vs restarting the container.

It's also important to understand how Kubernetes assigns QoS classes when scheduling pods, as it has an effect on pod scheduling and eviction. Below is the different QoS classes that can be assigned when a pod is scheduled:

- **QoS class of Guaranteed:**
  - Every Container in the Pod must have a memory limit and a memory request, and they must be the same.
  - Every Container in the Pod must have a CPU limit and a CPU request, and they must be the same.

- **QoS class of Burstable**
  - The Pod does not meet the criteria for QoS class **Guaranteed*.
  - At least one Container in the Pod has a memory or CPU request.

- **QoS class of Best Effort**
  - For a Pod to be given a QoS class of BestEffort, the Containers in the Pod must not have any memory or CPU limits or requests.

Below shows a diagram depicting QoS based on requests and limits.

![QoS](./img/qos.png)

**Failure to set limits for memory on pods can lead to a single pod starving the cluster of memory.**

If you want to ensure every pod gets at least a default request/limit, you can set a **LimitRange** on a namespace. If you perform the following command you can see in our cluster we have a LimitRange set on the Dev namespace.

```bash
# Check Limit Ranges in Dev Namespace
kubectl get limitrange dev-limit-range -n dev -o yaml
```

**You'll see that we have the following defaults:**

```yaml
- Request
  - CPU = 250m
  - Memory = 256Mi

- Limit
  - CPU = 500m
  - Memory = 512Mi
```

**It can't be stated enough of the importance of requests and limits to ensure your cluster is in a healthy state. You can read more on these topics in the **Key Links** at the end of this lab.**


TODO: Add VPA

## Metrics

- Low Disk Space
- Disk throttling

## Next Steps

[Validate Scenarios](validate-scenarios/README.md)

## Key Links

- [Setup Alerts for Performance Problems with Azure Monitor for Containers](https://docs.microsoft.com/en-us/azure/azure-monitor/insights/container-insights-alerts)
