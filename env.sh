#!/bin/bash

export PREFIX="bkrmpoc" # NOTE: Please make sure PREFIX is unique in your tenant, you must not have any hyphens '-' in the value.
export RG="${PREFIX}-rg"
export LOCATION="southeastasia"
export ACR_NAME="${PREFIX}-acr"
export VNET_NAME="${PREFIX}-vnet"
export AKSSUBNET_NAME="${PREFIX}-akssubnet"
export ILBSUBNET_NAME="${PREFIX}-ilbsubnet"
export APPGWSUBNET_NAME="${PREFIX}-appgwsubnet"
export SQLSUBNET_NAME="${PREFIX}-sqlsubnet"
# NOTE: DO NOT CHANGE FWSUBNET_NAME - This is currently a requirement for Azure Firewall.
export FWSUBNET_NAME="AzureFirewallSubnet"
export FWSUBNETMGMT_NAME="AzureFirewallManagementSubnet"
export FWNAME="${PREFIX}-fw"
export FWPUBLICIP_NAME="${PREFIX}-fwpublicip"
export FWPUBLICIPMGMT_NAME="${PREFIX}-fwmgmtpublicip"
export FWIPCONFIG_NAME="${PREFIX}-fwconfig"
export FWIPCONFIGMGMT_NAME="${PREFIX}-fwmgmtconfig"
export FWROUTE_TABLE_NAME="${PREFIX}-fwrt"
export FWROUTE_NAME="${PREFIX}-fwrn"
export AGNAME="${PREFIX}-ag"
export AGPUBLICIP_NAME="${PREFIX}-agpublicip"
