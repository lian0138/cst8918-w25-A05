terraform {
  required_version = ">= 1.1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.3"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "cloudinit" {
  # no extra config needed
}

# ========= Variables ============
variable "labelPrefix" {
  description = "Your college username, used for naming resources"
  type        = string
}

variable "region" {
  description = "Azure region for resources"
  type        = string
  default     = "canadacentral"
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "chris"
}

# ========= Resources ============

# Resource Group
resource "azurerm_resource_group" "web_rg" {
  name     = "${var.labelPrefix}-A05-RG"
  location = var.region
}

# Public IP
resource "azurerm_public_ip" "web_ip" {
  name                = "${var.labelPrefix}-web-ip"
  resource_group_name = azurerm_resource_group.web_rg.name
  location            = azurerm_resource_group.web_rg.location
  allocation_method   = "Dynamic"
}

# Virtual Network
resource "azurerm_virtual_network" "web_vnet" {
  name                = "${var.labelPrefix}-web-vnet"
  resource_group_name = azurerm_resource_group.web_rg.name
  location            = azurerm_resource_group.web_rg.location
  address_space       = ["10.0.0.0/16"]
}

# Subnet
resource "azurerm_subnet" "web_subnet" {
  name                 = "web-subnet"
  resource_group_name  = azurerm_resource_group.web_rg.name
  virtual_network_name = azurerm_virtual_network.web_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "web_nsg" {
  name                = "${var.labelPrefix}-web-nsg"
  resource_group_name = azurerm_resource_group.web_rg.name
  location            = azurerm_resource_group.web_rg.location

  security_rule {
    name                       = "allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-SSH"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# NIC
resource "azurerm_network_interface" "web_nic" {
  name                = "${var.labelPrefix}-web-nic"
  resource_group_name = azurerm_resource_group.web_rg.name
  location            = azurerm_resource_group.web_rg.location

  ip_configuration {
    name                          = "web-ip-config"
    subnet_id                     = azurerm_subnet.web_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.web_ip.id
  }
}

# Associate NSG to NIC
resource "azurerm_network_interface_security_group_association" "nic_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.web_nic.id
  network_security_group_id = azurerm_network_security_group.web_nsg.id
}

# Cloud-init config
data "cloudinit_config" "init" {
  gzip          = false
  base64_encode = true
  part {
    content_type = "text/x-shellscript"
    content      = file("${path.module}/init.sh")
  }
}

# Linux VM (Ubuntu 20.04-LTS to resolve image availability issue)
resource "azurerm_linux_virtual_machine" "web_vm" {
  name                  = "${var.labelPrefix}-web-vm"
  resource_group_name   = azurerm_resource_group.web_rg.name
  location              = azurerm_resource_group.web_rg.location
  admin_username        = var.admin_username
  size                  = "Standard_B1s"
  network_interface_ids = [azurerm_network_interface.web_nic.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("${path.module}/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "22.04-LTS" # changed clearly to stable available image
    version   = "latest"
  }

  custom_data = data.cloudinit_config.init.rendered
}

# ========= Outputs ============

output "resource_group_name" {
  value = azurerm_resource_group.web_rg.name
}

output "vm_public_ip" {
  value = azurerm_public_ip.web_ip.ip_address
}