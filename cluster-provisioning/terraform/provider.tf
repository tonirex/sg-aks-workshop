terraform {
  required_providers {
    azurerm = {
      version = ">=2.40.0"
    } 
    github = {
      version      = ">=4.1.0"
    }
    kubernetes = {
      version = ">=1.13.3"
    }
    tls = {
      version = ">=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}


provider "github" {
  token        = var.github_token
  organization = var.github_organization
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.demo.kube_admin_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.demo.kube_admin_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.demo.kube_admin_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.demo.kube_admin_config.0.cluster_ca_certificate)
}

provider "tls" {
}


