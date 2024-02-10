#resource "azurerm_storage_account" "storage" {
#  name                     = "${var.prefix}logs"
#  resource_group_name      = var.resource_group
#  location                 = var.location
#  account_tier             = "Standard"
# account_replication_type = "LRS"

#  tags = {
#    environment = "logs"
#  }
#}

data "azurerm_resource_group" "rg" {
  name = var.resource_group
}

resource "azurerm_container_registry" "acr" {
  name                = "${var.prefix}acr"
  resource_group_name = var.resource_group
  location            = var.location
  sku                 = "Standard"
  admin_enabled       = true
}

resource "azurerm_log_analytics_workspace" "demo" {
  name                = "${var.prefix}-aks-logs"
  location            = var.location
  resource_group_name = var.resource_group
  sku                 = "PerGB2018"
}

resource "azurerm_log_analytics_solution" "demo" {
  solution_name         = "ContainerInsights"
  location              = var.location
  resource_group_name   = var.resource_group
  workspace_resource_id = azurerm_log_analytics_workspace.demo.id
  workspace_name        = azurerm_log_analytics_workspace.demo.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }
}
resource "azurerm_kubernetes_cluster" "demo" {
  name                = "${var.prefix}-aks"
  location            = var.location
  dns_prefix          = "${var.prefix}-aks"
  resource_group_name = var.resource_group
  kubernetes_version  = var.kubernetes_version

  azure_active_directory_role_based_access_control {
    managed            = "true"
    azure_rbac_enabled = "false"
  }

  network_profile {
    network_plugin    = var.network_plugin
    network_policy    = var.network_policy
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
    outbound_type     = "userDefinedRouting"
  }

  linux_profile {
    admin_username = var.admin_username

    ssh_key {
      key_data = file(var.public_ssh_key_path)
    }
  }

  default_node_pool {
    name            = "default"
    node_count      = var.agent_count
    vm_size         = var.vm_size
    os_disk_size_gb = var.os_disk_size_gb
    type            = "VirtualMachineScaleSets"

    # Required for advanced networking
    vnet_subnet_id = var.azure_subnet_id
  }

  identity {
    type = "SystemAssigned"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.demo.id
  }

  azure_policy_enabled = true
  workload_identity_enabled = true
  oidc_issuer_enabled = true
}

resource "azurerm_role_assignment" "role1" {
  depends_on           = [azurerm_kubernetes_cluster.demo]
  scope                = data.azurerm_resource_group.rg.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.demo.identity[0].principal_id
}

resource "azurerm_role_assignment" "example" {
  principal_id                     = azurerm_kubernetes_cluster.demo.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}
