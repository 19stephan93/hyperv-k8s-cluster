# Kubernetes & HashiCorp Stack Cluster on Hyper-V

This project automates the setup of a local Kubernetes cluster and HashiCorp stack (Consul, Vault, Nomad) on Windows using Hyper-V virtualization, Packer for custom image creation, Terraform for provisioning, and Ansible for configuration management.

---

## Requirements

### Host Machine
- Windows 11 (recommended)
- WSL (Windows Subsystem for Linux) installed
- Hyper-V enabled
- Minimum 16GB RAM recommended

### Software to Install
- [Terraform](https://developer.hashicorp.com/terraform/install)
- [Packer](https://developer.hashicorp.com/packer/install)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) (install on your WSL/host Linux environment)

---

## Directory Overview

```text
.
├── packer/                     # Packer image build files
├── terraform-k8s/              # Terraform for Kubernetes cluster
├── terraform-hashicorp/        # Terraform for HashiCorp stack (separate state)
├── playbooks/                  # Ansible playbooks and inventory
│   ├── hosts                           # Ansible inventory (main file)
│   └── k8s/
│       ├── kubernetes_setup_playbook.yml   # Common K8s setup
│       ├── master_setup_playbook.yml       # K8s master setup + resource deployment
│       ├── worker_setup_playbook.yml       # K8s worker setup
│       └── deploy_resources_playbook.yml   # Deploy K8s resources (auto-included)
│   └── hashicorp/
│       ├── consul_setup_playbook.yml       # Consul cluster setup
│       ├── vault_setup_playbook.yml        # Vault cluster setup
│       └── nomad_setup_playbook.yml        # Nomad cluster setup
└── to_deploy/                  # Resources to deploy
    └── k8s/
        ├── metallb/            # MetalLB LoadBalancer configuration
        ├── envoy-gateway/      # Envoy Gateway ingress controller
        ├── dashboard/          # Kubernetes Dashboard
        └── whoami/             # Example application
```

---

## Architecture Overview

### Kubernetes Cluster (terraform-k8s/)
- **k8s-cp-001**: Control plane node (6GB RAM, 4 CPUs)
- **k8s-master-001**: Worker node (12GB RAM, 6 CPUs)
- **Ingress**: Envoy Gateway (replaces Traefik)
- **LoadBalancer**: MetalLB (IP pool: 192.168.1.200-250)
- **CNI**: Calico

### HashiCorp Stack (terraform-hashicorp/)
- **hashicorp-server-001**: 6GB RAM, 2 CPUs (runs Consul server, Vault server, and Nomad server)
- **hashicorp-client-001**: 12GB RAM, 6 CPUs (runs Consul client and Nomad client for workloads)

> **Note:** K8s and HashiCorp stacks use **separate Terraform directories** with independent state files, so they won't interfere with each other.

---
---
## Troubleshooting

### Kubernetes Envoy Gateway Not Updating Routes
```kubectl rollout restart deployment envoy-envoy-gateway-system-eg-5391c79d -n envoy-gateway-system```

### Nomad 

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

### 3. Update SSH Public Key in Packer Script
Edit `packer/script/setup.sh` and replace `<your_ansible_ssh_key>` with your public SSH key:

```bash
cat ~/.ssh/id_rsa.pub
```

### 4. Enable WinRM for Hyper-V Terraform Provider
Follow the setup instructions here:  
[https://github.com/taliesins/terraform-provider-hyperv?tab=readme-ov-file#setting-up-server-for-provider-usage](https://github.com/taliesins/terraform-provider-hyperv?tab=readme-ov-file#setting-up-server-for-provider-usage)

---

## Build and Provision

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

> ⏳ This will take a while. The image includes Kubernetes tools and HashiCorp stack (Consul, Vault, Nomad).

### 7. Prepare Images

After build completes, Packer will produce:

```text
packer/output-ubuntu/Virtual Hard Disks/ubuntu-packer.vhdx
```

Manually copy and rename it for each node:

**For Kubernetes:**
```text
hdds/ubuntu-packer-k8s-cp-1.vhdx
hdds/ubuntu-packer-k8s-worker-1.vhdx
```

**For HashiCorp Stack:**
```text
hdds/ubuntu-packer-hashicorp-server-1.vhdx
hdds/ubuntu-packer-hashicorp-client-1.vhdx
```

Place all VHDX files in the `hdds/` directory at the root of the project.

---

## Run Terraform

### Option A: Kubernetes Cluster Only

```bash
cd terraform-k8s
terraform init
terraform plan
terraform apply
```

### Option B: HashiCorp Stack Only

```bash
cd terraform-hashicorp
terraform init
terraform plan
terraform apply
```

> **Important:** These are separate Terraform configurations with independent state files. Running `terraform apply` in one directory will NOT affect the other.

After Terraform completes, the VMs will be created and configured with static IPs.

---

## Configure with Ansible

### 8. Update Ansible Inventory

Update `playbooks/hosts` file with the IP addresses from Terraform output:

**For Kubernetes:**
```ini
[k8s_masters]
k8s-cp-001 ansible_host=<MASTER_IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa

[k8s_workers]
k8s-master-001 ansible_host=<WORKER_IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa

# Kubernetes group (combines masters and workers)
[k8s_all:children]
k8s_masters
k8s_workers
```

**For HashiCorp Stack:**
```ini
[consul_servers]
hashicorp-server-001 ansible_host=192.168.1.150 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa

[consul_clients]
hashicorp-client-001 ansible_host=192.168.1.161 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa

# ... vault_servers, nomad_servers, etc.
```

### 9. Test Ansible Connection

**For Kubernetes nodes:**
```bash
cd playbooks
ansible -i hosts k8s_all -m ping
```

**For HashiCorp nodes:**
```bash
ansible -i hosts hashicorp_all -m ping
```

> **Important:** The inventory uses separate groups (`k8s_all` and `hashicorp_all`) to ensure playbooks only affect their intended targets and don't interfere with each other.

---

## Setup Kubernetes Cluster

### 10. Run Kubernetes Playbooks

The setup process is fully automated and will deploy all resources in one go.

**Run these three playbooks in order:**

```bash
cd playbooks
ansible-playbook -i hosts k8s/kubernetes_setup_playbook.yml
ansible-playbook -i hosts k8s/master_setup_playbook.yml  (this will fail at some step, run the next one so the worker joins the cluster and run this again)
ansible-playbook -i hosts k8s/worker_setup_playbook.yml
```

> **Note:** You do NOT need to manually run `deploy_resources_playbook.yml` - it's automatically triggered by `master_setup_playbook.yml`

**What happens automatically:**

1. **kubernetes_setup_playbook.yml** - Applies to **all K8s nodes** (`k8s_all`):
   - Updates packages and reboots
   - Disables swap
   - Installs and configures containerd
   - Installs Kubernetes components (kubectl, kubeadm, kubelet)

2. **master_setup_playbook.yml** - Applies to **K8s master only** (`k8s_masters`):
   - Initializes the cluster with kubeadm
   - Installs Calico CNI
   - Waits for all nodes to be ready
   - **Automatically calls `deploy_resources_playbook.yml`** (you don't run this manually)

3. **deploy_resources_playbook.yml** - Automatically triggered by master_setup_playbook (applies to `k8s_masters`):
   - Copies all manifests from `to_deploy/k8s/` to the master node
   - Installs **MetalLB** with IP pool 192.168.1.200-250
   - Installs **Envoy Gateway** as ingress controller
   - Creates the Gateway instance and waits for LoadBalancer IP
   - Deploys **Kubernetes Dashboard** with admin user and HTTPRoute
   - Deploys **Whoami** example application
   - Generates and saves dashboard admin token to `/home/ubuntu/dashboard-token.txt`
   - Displays deployment summary with all endpoints

4. **worker_setup_playbook.yml** - Applies to **K8s workers** (`k8s_workers`):
   - Joins worker nodes to the cluster

> ⏳ This process takes 10-15 minutes. The playbook will wait for each component to be ready before proceeding.

> **Note:** These playbooks will **ONLY** run on Kubernetes nodes and will **NOT** affect your HashiCorp/Nomad cluster.

### 11. Verify Kubernetes Cluster

SSH into the master node and run:

```bash
kubectl get nodes
```

You should see all nodes in **Ready** state.

Check deployed resources:

```bash
# Check MetalLB
kubectl get pods -n metallb-system

# Check Envoy Gateway
kubectl get gateway -n envoy-gateway-system
kubectl get svc -n envoy-gateway-system

# Check Dashboard
kubectl get pods -n kubernetes-dashboard

# Check Whoami example
kubectl get pods -n whoami
kubectl get httproute -n whoami
```

### 12. Access Kubernetes Dashboard

The Dashboard admin token is automatically generated and saved to `/home/ubuntu/dashboard-token.txt` on the master node.

To retrieve it:

```bash
ssh ubuntu@<MASTER_IP> cat ~/dashboard-token.txt
```

Access the dashboard at: `http://dashboard.k8s.local` (make sure to add the Gateway IP to your hosts file or DNS)

---

## Kubernetes Components Deployed

| Component       | Purpose                          | Namespace              |
|-----------------|----------------------------------|------------------------|
| **MetalLB**     | LoadBalancer for bare metal      | metallb-system         |
| **Envoy Gateway** | Ingress controller (HTTP only) | envoy-gateway-system   |
| **Calico**      | CNI network plugin               | kube-system            |
| **Dashboard**   | Web UI for cluster management    | kubernetes-dashboard   |
| **Whoami**      | Example application              | whoami                 |

### Accessing Applications

Get the Envoy Gateway LoadBalancer IP:
```bash
kubectl get svc -n envoy-gateway-system
```

Add to your `/etc/hosts` or `C:\Windows\System32\drivers\etc\hosts`:
```
<GATEWAY_IP>  whoami.local
<GATEWAY_IP>  dashboard.k8s.local
```

Then access:
- **Whoami**: http://whoami.local
- **Dashboard**: http://dashboard.k8s.local

---

## Setup HashiCorp Stack (Consul, Vault, Nomad)

### 13. Run HashiCorp Playbooks

Run the playbooks in this order:

```bash
cd playbooks

# 1. Setup Consul cluster first (service discovery)
ansible-playbook -i hosts hashicorp/consul_setup_playbook.yml

# 2. Setup Vault cluster (secrets management)
ansible-playbook -i hosts hashicorp/vault_setup_playbook.yml

# 3. Setup Nomad cluster (workload orchestration)
ansible-playbook -i hosts hashicorp/nomad_setup_playbook.yml
```

> **Note:** These playbooks will **ONLY** run on HashiCorp nodes (`hashicorp_all`) and will **NOT** affect your Kubernetes cluster.

### 14. Initialize and Unseal Vault

After running the Vault playbook, SSH into the Vault server:

```bash
ssh ubuntu@192.168.1.150
```

Check Vault status:
```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault status
```

The initialization keys are stored in `/root/vault_init.json`. To unseal Vault:

```bash
sudo cat /root/vault_init.json
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>
```

> ⚠️ **IMPORTANT**: Store the unseal keys and root token securely, then delete `/root/vault_init.json`!

### 15. Verify HashiCorp Stack

**Consul UI:** `http://192.168.1.150:8500`

**Vault UI:** `http://192.168.1.150:8200`

**Nomad UI:** `http://192.168.1.150:4646`

**Check Consul members:**
```bash
ssh ubuntu@192.168.1.150
consul members
```

**Check Nomad status:**
```bash
nomad server members
nomad node status
```

You should see:
- 1 Consul server + 1 Consul client
- 1 Vault server
- 1 Nomad server + 1 Nomad client

---

## Web UIs

### Kubernetes
| Service         | URL                              | Access                           |
|-----------------|----------------------------------|----------------------------------|
| Dashboard       | `http://dashboard.k8s.local`     | Token in ~/dashboard-token.txt   |
| Whoami (test)   | `http://whoami.local`            | Public access                    |

### HashiCorp Stack
| Service    | URL                          | Description              |
|------------|------------------------------|--------------------------|
| Consul     | `http://192.168.1.150:8500`  | Service discovery UI     |
| Vault      | `http://192.168.1.150:8200`  | Secrets management UI    |
| Nomad      | `http://192.168.1.150:4646`  | Workload orchestration UI|

---

## External Envoy Proxy (Future)

The architecture is designed to support an external Envoy proxy for SSL termination and unified routing:

```
External Envoy (SSL termination)
         |
         |--- HTTP ---> K8s Envoy Gateway (MetalLB IP) ---> Services
         |
         |--- HTTP ---> Nomad Consul Ingress Gateway ---> Services
```

This allows:
- Single SSL certificate management point
- Routing based on hostname/path to either K8s or Nomad
- Both clusters operate with HTTP only internally

---

## Customizing Deployments

### Modify MetalLB IP Pool

Edit `to_deploy/k8s/metallb/metallb-config.yml`:

```yaml
spec:
  addresses:
  - 192.168.1.200-192.168.1.250  # Change this range
```

Then re-run the deployment:
```bash
kubectl apply -f to_deploy/k8s/metallb/metallb-config.yml
```

Or re-run the master setup playbook to redeploy everything.

### Deploy Additional Applications

Create HTTPRoute manifests in `to_deploy/k8s/` and apply them:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: my-namespace
spec:
  parentRefs:
  - name: eg
    namespace: envoy-gateway-system
  hostnames:
  - "myapp.local"
  rules:
  - backendRefs:
    - name: my-service
      port: 80
```

Apply with:
```bash
kubectl apply -f to_deploy/k8s/my-app/
```

---

## Ansible Inventory Groups

The inventory file uses the following groups to keep K8s and HashiCorp clusters isolated:

### Kubernetes Groups
- **k8s_masters**: Kubernetes control plane nodes
- **k8s_workers**: Kubernetes worker nodes
- **k8s_all**: All Kubernetes nodes (parent group)

### HashiCorp Groups
- **consul_servers**: Consul server nodes
- **consul_clients**: Consul client nodes
- **vault_servers**: Vault server nodes
- **nomad_servers**: Nomad server nodes
- **nomad_clients**: Nomad client nodes
- **hashicorp_servers**: All HashiCorp server nodes (parent group)
- **hashicorp_clients**: All HashiCorp client nodes (parent group)
- **hashicorp_all**: All HashiCorp nodes (parent group)

This separation ensures that running K8s playbooks won't affect HashiCorp nodes and vice versa.

---

## Security Notes

### Generate Your Own Encryption Keys

For production use, generate your own encryption keys:

**Consul:**
```bash
consul keygen
```

**Nomad:**
```bash
nomad operator gossip keyring generate
```

Update the playbooks with your generated keys before running them.

---

## Cleanup

To destroy Kubernetes VMs only:
```bash
cd terraform-k8s
terraform destroy
```

To destroy HashiCorp stack VMs only:
```bash
cd terraform-hashicorp
terraform destroy
```

---

## Troubleshooting

### VMs not getting IP addresses
- Ensure the Hyper-V virtual switch is configured correctly
- Check that DHCP is available on your network
- Verify MAC addresses in Terraform configurations are unique

### Ansible connection issues
- Verify SSH keys are correctly added to authorized_keys
- Check that the VM IPs are reachable from WSL
- Test with: `ssh ubuntu@<VM_IP>`

### Ansible applying to wrong nodes
- Verify inventory groups are correct (`k8s_all` vs `hashicorp_all`)
- Use `ansible -i hosts <group> --list-hosts` to see which hosts are targeted
- Always check playbook `hosts:` directive matches intended group

### MetalLB not assigning IPs
- Check that the IP range doesn't conflict with DHCP
- Verify MetalLB pods are running: `kubectl get pods -n metallb-system`
- Check configuration: `kubectl get ipaddresspool -n metallb-system`

### Envoy Gateway not getting LoadBalancer IP
- Ensure MetalLB is running and configured
- Check Gateway status: `kubectl describe gateway eg -n envoy-gateway-system`
- View service: `kubectl get svc -n envoy-gateway-system`

### Applications not accessible
- Verify HTTPRoute is configured: `kubectl get httproute -A`
- Check Gateway has an external IP
- Ensure hostname is in your hosts file
- Test with: `curl -H "Host: whoami.local" http://<GATEWAY_IP>`

### Consul/Vault/Nomad not starting
- Check logs: `journalctl -u consul`, `journalctl -u vault`, `journalctl -u nomad`
- Verify firewall rules allow the required ports
- Ensure all services can resolve hostnames

### Terraform keeps recreating VMs
- The configuration includes `lifecycle` blocks to prevent unnecessary recreation
- If MAC addresses cause issues, they are in the `ignore_changes` list
- Always run `terraform plan` first to see what will change

### Required Ports

**Kubernetes:**
| Component | Port  | Protocol | Description           |
|-----------|-------|----------|-----------------------|
| API Server| 6443  | TCP      | Kubernetes API        |
| kubelet   | 10250 | TCP      | Kubelet API           |
| Envoy GW  | 80    | TCP      | HTTP ingress          |

**HashiCorp Stack:**
| Service | Port  | Protocol | Description           |
|---------|-------|----------|-----------------------|
| Consul  | 8500  | TCP      | HTTP API / UI         |
| Consul  | 8600  | TCP/UDP  | DNS                   |
| Consul  | 8301  | TCP/UDP  | Serf LAN              |
| Consul  | 8302  | TCP/UDP  | Serf WAN              |
| Consul  | 8300  | TCP      | Server RPC            |
| Vault   | 8200  | TCP      | HTTP API / UI         |
| Vault   | 8201  | TCP      | Cluster communication |
| Nomad   | 4646  | TCP      | HTTP API / UI         |
| Nomad   | 4647  | TCP      | RPC                   |
| Nomad   | 4648  | TCP/UDP  | Serf                  |

---

## Advanced Configuration

### Scaling the Kubernetes Cluster

To add more worker nodes:

1. Edit `terraform-k8s/main.tf` and add entries to `locals.nodes` list
2. Create corresponding VHDX files in the `hdds/` directory
3. Run `terraform apply`
4. Update `playbooks/hosts` with the new worker entries in the `[k8s_workers]` section
5. Run `ansible-playbook -i hosts k8s/kubernetes_setup_playbook.yml` on new nodes
6. Run `ansible-playbook -i hosts k8s/worker_setup_playbook.yml` on new nodes

### Scaling the HashiCorp Stack

To add more client nodes for additional workload capacity:

1. Edit `terraform-hashicorp/main.tf` and add entries to the nodes list
2. Create corresponding VHDX files in the `hdds/` directory
3. Run `terraform apply`
4. Update `playbooks/hosts` with the new node entries in the appropriate HashiCorp groups
5. Run the HashiCorp playbooks again

### Using Different Network Configuration

If you need to use a different network or static IPs:

1. Update the MAC addresses in Terraform configurations
2. Configure your DHCP server to assign specific IPs based on MAC addresses
3. Update `playbooks/hosts` with the correct IP addresses
4. Update MetalLB IP pool in `to_deploy/k8s/metallb/metallb-config.yml`

---

## What Gets Deployed Automatically

When you run the Kubernetes playbooks, the following are automatically deployed:

✅ **MetalLB** - LoadBalancer implementation for bare metal  
✅ **Envoy Gateway** - Modern ingress controller using Gateway API  
✅ **Kubernetes Dashboard** - Web-based cluster management UI  
✅ **Whoami Example** - Test application to verify routing  
✅ **Admin Service Account** - For dashboard access  
✅ **HTTPRoutes** - Routing configuration for all applications  

All resources in `to_deploy/k8s/` are automatically applied during the initial setup!

---

## License

See [LICENSE](LICENSE) file.
