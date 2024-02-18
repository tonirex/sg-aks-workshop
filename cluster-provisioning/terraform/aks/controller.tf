resource "null_resource" "configure_kubeconfig" {
  provisioner "local-exec" {
    command = <<EOF
      az aks get-credentials --resource-group ${var.resource_group} --name ${azurerm_kubernetes_cluster.aks.name} --admin --overwrite-existing
      kubectl apply -f cert-manager.yaml
    EOF
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}
