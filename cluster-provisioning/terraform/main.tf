resource "azurerm_storage_account" "storage" {
  name                     = "${var.prefix}logs"
  resource_group_name      = var.resource_group
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = "logs"
  }
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

  role_based_access_control {
    enabled = true

    azure_active_directory {
      managed = true
    }
  }
  addon_profile {
    kube_dashboard {
      enabled = false
    }
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = azurerm_log_analytics_workspace.demo.id
    }
    azure_policy {
      enabled = true
    }
  }
  network_profile {
    load_balancer_sku  = "standard"
    network_plugin     = var.network_plugin
    network_policy     = var.network_policy
    service_cidr       = var.service_cidr
    dns_service_ip     = var.dns_service_ip
    docker_bridge_cidr = var.docker_bridge_cidr
  }

  lifecycle {
        ignore_changes = [
            # default_node_pool[0].node_count,
            default_node_pool[0].vnet_subnet_id,
            windows_profile
        ]
    }
}

data "azurerm_virtual_network" "vnet" {
  name                = var.azure_vnet_name
  resource_group_name = var.resource_group
}

resource "azurerm_role_assignment" "role1" {
  depends_on = [azurerm_kubernetes_cluster.demo]
  scope                = data.azurerm_virtual_network.vnet.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_kubernetes_cluster.demo.identity[0].principal_id
}

resource "azurerm_role_assignment" "role2" {
  depends_on = [azurerm_kubernetes_cluster.demo]
  scope                = azurerm_kubernetes_cluster.demo.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_kubernetes_cluster.demo.identity[0].principal_id
}
