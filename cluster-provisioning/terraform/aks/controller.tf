resource "null_resource" "configure_kubeconfig" {
  provisioner "local-exec" {
    command = <<EOF
      az aks get-credentials --resource-group ${var.resource_group} --name ${azurerm_kubernetes_cluster.aks.name} --admin --overwrite-existing
      kubectl apply -f cert-manager.yaml
      kubectl wait --for=condition=ready pod -n cert-manager -l app=cert-manager
      kubectl wait --for=condition=ready pod -n cert-manager -l app=cainjector
      kubectl wait --for=condition=ready pod -n cert-manager -l app=webhook
      kubectl apply -f cert.yml
      kubectl apply -f k8s.yml
    EOF
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}
