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
  user     = "19stephan93@gmail.com"
  password = "Wu9CiF7P5q+z3*J#"
}

locals {
  # HashiCorp stack servers (Consul, Vault, Nomad servers)
  hashicorp_servers = [
    {
      name = "hashicorp-server-001"
      vhdx_path = "E:\\projects\\technovateit-solutions\\hyperv-k8s-cluster\\hdds\\ubuntu-packer-hashicorp-server-1.vhdx"
      mac_address = "00:15:5D:01:80:50",
      memory_mb = 6144,
      cpu_count = 2,
      ip_address = "192.168.1.150"
    }
  ]

  # HashiCorp stack clients (Nomad clients/workers) - these run the actual workloads
  hashicorp_clients = [
    {
      name = "hashicorp-client-001"
      vhdx_path = "E:\\projects\\technovateit-solutions\\hyperv-k8s-cluster\\hdds\\ubuntu-packer-hashicorp-client-1.vhdx"
      mac_address = "00:15:5D:01:80:61",
      memory_mb = 12288,
      cpu_count = 6,
      ip_address = "192.168.1.161"
    }
  ]

  # All HashiCorp nodes
  all_hashicorp_nodes = concat(local.hashicorp_servers, local.hashicorp_clients)
}

# Provisioning HashiCorp nodes
resource "hyperv_machine_instance" "hashicorp_node" {
  for_each   = { for node in local.all_hashicorp_nodes : node.name => node }
  name       = each.value.name
  generation = 2
  memory_startup_bytes = each.value.memory_mb * 1024 * 1024
  processor_count      = each.value.cpu_count

  static_memory = true

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
    name        = var.switch_name
    switch_name = var.switch_name

    dynamic_mac_address = false
    static_mac_address  = each.value.mac_address
  }

  hard_disk_drives {
    controller_location = "0"
    controller_number   = "0"
    path                = each.value.vhdx_path
  }

  lifecycle {
    ignore_changes = [
      # Ignore changes to the VHDX path to prevent recreation when disk is modified
      hard_disk_drives[0].path,
      # Ignore MAC address format changes to prevent VM restarts
      network_adaptors[0].static_mac_address,
    ]
  }
}

data "external" "hashicorp_node_ip" {
  depends_on = [hyperv_machine_instance.hashicorp_node]
  for_each   = { for node in local.all_hashicorp_nodes : node.name => node }

  program = ["powershell", "../scripts/get_node_ip.ps1", "-NodeName", each.key, "-SwitchName", "\"${var.switch_name}\""]
}

# Output DHCP IPs for initial Ansible inventory setup
output "HashiCorp_Node_IPs" {
  description = "DHCP IPs (current) for each node - use these in hosts_initial"
  value = {
    for node in local.all_hashicorp_nodes :
    node.name => data.external.hashicorp_node_ip[node.name].result["ip"]
  }
}
