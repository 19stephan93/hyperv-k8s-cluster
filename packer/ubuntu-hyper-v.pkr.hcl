packer {
  required_plugins {
    hyperv = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/hyperv"
    }
  }
}

variable "iso_path" {
  type    = string
  default = "../iso/ubuntu-24.04.2-live-server-amd64.iso"
}

source "hyperv-iso" "ubuntu" {
  iso_url             = var.iso_path
  # iso_checksum        = "sha256:<your_sha256>"
  iso_checksum        = "none" # to disable checksum

  communicator        = "ssh"
  ssh_username        = "ubuntu"
  ssh_password        = "ubuntu"
  ssh_timeout         = "15m"

  shutdown_command    = "echo 'packer' | sudo -S shutdown -P now"

  vm_name             = "ubuntu-packer"
  generation          = 2
  switch_name         = "Bridge"
  cpus                = 4 # 4 cores
  memory              = 4096 # 4gb

  disk_size           = 10000 # 10gb
  enable_secure_boot  = false
  boot_wait           = "5s"

  boot_command = [
    "<esc><wait>",
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds=\"nocloud-net;seedfrom=http://{{.HTTPIP}}:{{.HTTPPort}}/\"",
    "<enter><wait>",
    "initrd /casper/initrd",
    "<enter><wait>",
    "boot",
    "<enter>"
  ]

  http_directory = "./http"
}

build {
  sources = ["source.hyperv-iso.ubuntu"]

  provisioner "shell" {
    script = "./script/setup.sh"
  }
}
