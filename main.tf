terraform {
  required_providers {
    vsphere = {
      source = "hashicorp/vsphere"
    }
  }
}


############################################################
variable "vsphere_server" {
  type = string
}
variable "vsphere_datacenter" {
  type = string
}
variable "vsphere_compute_cluster" {
  type = string
}
variable "vsphere_datastore_cluster" {
  type = string
}
variable "vsphere_iso_datastore" { 
  type = string
}
variable "vsphere_iso_DestDir" {
  type = string
  default = null
}
variable "vsphere_network" {
type = string
default = "Default"
}
variable "vsphere_username" {
  type = string
}
variable "vsphere_password" {
  sensitive = true
}

variable "guestHostname" {
  type = string
  validation {
    condition     = can(regex("^.*\\..*\\..*$", var.guestHostname)) # Must be a FQDN
    error_message = "Hostname string must be a FQDN (e.g. test.domain.local)"
  }
}
variable "vsphere_guest_cores" {
  type    = number
  default = null
}
variable "vsphere_guest_cores_per_socket" {
  type    = number
  default = null
}
variable "vsphere_guest_memory_megabytes" {
  type    = number
  default = null
}
variable "vsphere_guest_folder" {
  type    = string
  default = null
}
variable "vsphere_guest_diskgb" {
  type    = number
  default = null
}


############################################################
############################################################

provider "vsphere" {
  user                 = var.vsphere_username
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}


data "vsphere_datacenter" "datacenter" {
  name          = var.vsphere_datacenter
}

data "vsphere_datastore" "iso_datastore" {
  name          = var.vsphere_iso_datastore
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.vsphere_compute_cluster
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "network" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore_cluster" "datastore_cluster" {
  name          = var.vsphere_datastore_cluster
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

############################################################

#resource "random_uuid" "terraform" {
#}

#resource "random_uuid" "ipxe_iso" {
#}

resource "vsphere_file" "ipxe_iso" {
  datacenter  = data.vsphere_datacenter.datacenter.name
  datastore   = data.vsphere_datastore.iso_datastore.name
  source_file = "ipxe/src/bin-x86_64-efi/ipxe.iso"
  destination_file = "${var.vsphere_iso_DestDir}/ipxe.iso" 
}


resource "vsphere_virtual_machine" "terraform" {

  depends_on             = [vsphere_file.ipxe_iso]

  name                   = var.guestHostname
  firmware               = "efi"
  resource_pool_id       = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_cluster_id   = data.vsphere_datastore_cluster.datastore_cluster.id
  num_cpus               = var.vsphere_guest_cores
  num_cores_per_socket   = try(var.vsphere_guest_cores_per_socket, var.vsphere_guest_cores)
  cpu_hot_add_enabled    = true
  cpu_hot_remove_enabled = true
  memory                 = var.vsphere_guest_memory_megabytes
  memory_hot_add_enabled = true
  folder                 = var.vsphere_guest_folder

  guest_id               = "rhel9_64Guest"
  #guest_id               = "otherlinux64guest"
  # https://docs.vmware.com/en/VMware-HCX+/services/Using-Managing-HCXPlus/GUID-D4FFCBD6-9FEC-44E5-9E26-1BD0A2A81389.html

  disk {
    label            = "disk0"
    size             = var.vsphere_guest_diskgb
    thin_provisioned = true
  }

  cdrom {
    datastore_id = data.vsphere_datastore.iso_datastore.id
    path         = "${var.vsphere_iso_DestDir}/ipxe.iso"
  }

  network_interface {
    network_id = data.vsphere_network.network.id
  }

  wait_for_guest_ip_timeout = 10

}
