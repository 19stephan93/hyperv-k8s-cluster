terraform {
  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = ">= 1.0.3"
    }
  }
}

provider "hyperv" {
  host = "localhost"
  # 5986 for https and 5985 for http WinRM connection
  # port = 5986
  port = 5985
  # enable this to run over http
  https = false
  insecure = true
  user     = "your_windows_user"
  password = "your_windows_password"
}

locals {
  nodes = [
    {
      name = "master-node"
      # Change to the outputed packer image
      vhdx_path = "E:\\projects\\technovateit-solutions\\hyperv-k8s-cluster\\packer\\output-ubuntu\\Virtual Hard Disks\\ubuntu-packer-master.vhdx"
      mac_address = "00:15:5D:01:80:40",
      memory_mb = 4096,
      cpu_count = 2
    },
    {
      name = "worker-node"
      # Change to the outputed packer image
      vhdx_path = "E:\\projects\\technovateit-solutions\\hyperv-k8s-cluster\\packer\\output-ubuntu\\Virtual Hard Disks\\ubuntu-packer-worker.vhdx"
      mac_address = "00:15:5D:01:80:41",
      memory_mb = 8192,
      cpu_count = 4
    }
  ]
}

# provisioning nodes
resource "hyperv_machine_instance" "node" {
  for_each   = { for node in local.nodes : node.name => node }
  name       = each.value.name
  generation = 2
  # change in variables.tf
  memory_startup_bytes = each.value.memory_mb * 1024 * 1024
  processor_count      = each.value.cpu_count

  static_memory = true

  ## this is default value to prevent terraform from provisioning the VMs again.
  vm_processor {
    compatibility_for_migration_enabled               = false
    compatibility_for_older_operating_systems_enabled = false
    enable_host_resource_protection                   = false
    expose_virtualization_extensions                  = false
    hw_thread_count_per_core                          = 0
    maximum                                           = 100
    maximum_count_per_numa_node                       = 8
    maximum_count_per_numa_socket                     = 1
    relative_weight                                   = 100
    reserve                                           = 0
  }

  vm_firmware {
    enable_secure_boot = "Off"

    boot_order {
      boot_type           = "HardDiskDrive"
      controller_number   = "0"
      controller_location = "0"
    }

    boot_order {
      boot_type            = "NetworkAdapter"
      network_adapter_name = var.switch_name
    }
  }

  network_adaptors {
    # change in variables.tf
    name        = var.switch_name
    switch_name = var.switch_name

    ## to set static mac address
    dynamic_mac_address = false
    static_mac_address  = each.value.mac_address
  }

  hard_disk_drives {
    controller_location = "0"
    controller_number   = "0"
    path                = each.value.vhdx_path
  }
}

data "external" "node_ip" {
  depends_on = [hyperv_machine_instance.node]
  for_each   = { for node in local.nodes : node.name => node }

  program = ["powershell", "./script/get_node_ip.ps1", "-NodeName", each.key, "-SwitchName", "\"${var.switch_name}\""]
}

# change hostname and set static ip
resource "null_resource" "modify_node" {
  for_each = data.external.node_ip
  connection {
    host = each.value.result["ip"]
    # username and password created with packer
    user     = "ubuntu"
    password = "ubuntu"
    # private_key = file("~/.ssh/id_rsa")
    type = "ssh"
  }

  provisioner "file" {
    source      = "${path.module}/script/modify_node.sh"
    destination = "/tmp/modify_node.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/modify_node.sh",
      "sudo /tmp/modify_node.sh ${each.key} ${each.value.result["ip"]} ${each.value.result["prefix_length"]} ${each.value.result["gateway"]}"
    ]
  }
}

# outputing nodes ip
output "IPAddresses" {
  depends_on = [null_resource.modify_node]
  value = {
    for node_name, node_data in data.external.node_ip :
    node_name => node_data.result["ip"]
  }
}
