terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.91.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.5"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "tls" {
}

#provider "kubernetes" {
#  host                   = azurerm_kubernetes_cluster.demo.kube_admin_config.0.host
#  client_certificate     = base64decode(azurerm_kubernetes_cluster.demo.kube_admin_config.0.client_certificate)
#  client_key             = base64decode(azurerm_kubernetes_cluster.demo.kube_admin_config.0.client_key)
#  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.demo.kube_admin_config.0.cluster_ca_certificate)
#}