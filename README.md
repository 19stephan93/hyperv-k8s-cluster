# Kubernetes Cluster on Hyper-V using Packer, Terraform, and Ansible

This project automates the setup of a local Kubernetes cluster on Windows using Hyper-V virtualization, Packer for custom image creation, Terraform for provisioning, and Ansible for configuration management.

---

## Requirements

### Host Machine
- Windows 11 (recommended)
- WSL (Windows Subsystem for Linux) installed
- Hyper-V enabled

### Software to Install
- [Terraform](https://developer.hashicorp.com/terraform/install)
- [Packer](https://developer.hashicorp.com/packer/install)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) (install on your WSL/host Linux environment)

---

## Directory Overview

```text
.
├── packer/                 # Packer image build files
├── terraform/              # Terraform provisioning configs
└── playbooks/              # Ansible playbooks and inventory
```

---

## Setup Instructions

### 1. Install Required Tools
- Install **Packer** and **Terraform** on your **Windows** machine.
- Install **Ansible** inside your WSL (recommended).

### 2. Generate SSH Keypair
Run this on your WSL:

```bash
ssh-keygen
```

This key will be used for Ansible to access the virtual machines.

### 3. Enable WinRM for Hyper-V Terraform Provider
Follow the setup instructions here:  
[https://github.com/taliesins/terraform-provider-hyperv?tab=readme-ov-file#setting-up-server-for-provider-usage](https://github.com/taliesins/terraform-provider-hyperv?tab=readme-ov-file#setting-up-server-for-provider-usage)

---

## Build and Provision

### 4. Customize Configuration
Adjust `packer/ubuntu-hyper-v.pkr.hcl` as needed.

### 5. Clone the Repository

```bash
git clone https://github.com/0xhydropho/hyperv-k8s-cluster
cd hyperv-k8s-cluster
```

### 6. Run Packer

```bash
cd packer
packer init .
packer build .
```

>  It will take a while.

### 7. Prepare Images

After build completes, Packer will produce:

```text
packer/output-ubuntu/Virtual Hard Disks/ubuntu-packer.vhdx
```

Manually copy and rename it:

```text
ubuntu-packer-master.vhdx
ubuntu-packer-worker.vhdx
```

---

## Run Terraform

### 8. Customize Configuration
Adjust `terraform/*.tf` as needed (e.g., number of nodes, IP allocation, etc.).

### 9. Initialize and Apply

```bash
terraform init
terraform plan
terraform apply
```

After apply, Terraform will output the IP addresses of your VMs.

---

## Configure with Ansible

### 10. Add VM IPs to Ansible Inventory

Edit the `hosts` file and add the IPs under `[masters]` and `[workers]`.

### 11. Verify Inventory

```bash
ansible-inventory -i hosts --list -y
```

### 12. Trust SSH Fingerprints

```bash
ssh-keyscan -H <vm_ip> >> ~/.ssh/known_hosts
```

Do this for each master and worker IP.

### 13. Test Ansible Connection

```bash
ansible -i hosts all -m ping
```

### 14. Run Ansible Playbooks

```bash
ansible-playbook -i hosts kubernetes_setup_playbook.yml
ansible-playbook -i hosts master_setup_playbook.yml
ansible-playbook -i hosts worker_setup_playbook.yml
```

---

## Verify Kubernetes Cluster

SSH into the master node:

```bash
ssh user@<master-ip>
```

Then run:

```bash
kubectl get nodes
```

You should see all nodes (master and workers) in **Ready** state.

---
