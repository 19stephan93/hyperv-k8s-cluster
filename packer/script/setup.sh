#! /bin/bash

sudo apt update
sudo apt upgrade -y

sudo systemctl enable ssh

# Install required packages
sudo apt install -y curl gnupg lsb-release software-properties-common unzip jq

# Add HashiCorp GPG key and repository
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update

# Install HashiCorp stack
sudo apt install -y consul vault nomad

# Create directories for HashiCorp stack
sudo mkdir -p /etc/consul.d /opt/consul/data
sudo mkdir -p /etc/vault.d /opt/vault/data
sudo mkdir -p /etc/nomad.d /opt/nomad/data

# Create consul user and group
sudo useradd --system --home /etc/consul.d --shell /bin/false consul || true
sudo chown -R consul:consul /etc/consul.d /opt/consul

# Create vault user and group
sudo useradd --system --home /etc/vault.d --shell /bin/false vault || true
sudo chown -R vault:vault /etc/vault.d /opt/vault

# Create nomad user and group
sudo useradd --system --home /etc/nomad.d --shell /bin/false nomad || true
sudo chown -R nomad:nomad /etc/nomad.d /opt/nomad

# Enable memory locking for Vault (security best practice)
sudo setcap cap_ipc_lock=+ep $(which vault)

# Install Docker (required for Nomad Docker driver)
sudo apt install -y apt-transport-https ca-certificates
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Enable Docker
sudo systemctl enable docker

# Install CNI plugins (required for Nomad networking)
CNI_VERSION="v1.3.0"
sudo mkdir -p /opt/cni/bin
curl -sSL "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" | sudo tar -xz -C /opt/cni/bin

cat << EOF | sudo tee /home/ubuntu/.ssh/authorized_keys
<your_ansible_ssh_key>
EOF
