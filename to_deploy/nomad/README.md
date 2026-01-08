# Nomad Deployment with Envoy Ingress

This directory contains Nomad job specifications for deploying applications with Envoy as the ingress controller.

## Architecture

```
Internet → Router → External Envoy (SSL Term) → Envoy Ingress (Nomad) → Nomad Services
                                                     192.168.1.150:8080
```

**How it works:**
1. **External Envoy** (Docker Compose) handles SSL termination and routes to Nomad
2. **Envoy Ingress** (Nomad job) runs on port 8080, discovers services from Consul
3. **Nomad Services** (whoami, etc.) register in Consul with dynamic ports
4. **Consul template** in Envoy auto-updates configuration when services change

## Prerequisites

1. **Nomad cluster** running and accessible
2. **Consul** for service discovery (required for this setup)
3. **Docker** driver enabled on Nomad clients

## Quick Start

### 1. Deploy Envoy Ingress Controller

This creates an Envoy instance that listens on port 8080 and auto-discovers services from Consul:

```bash
# Deploy the Envoy ingress
nomad job run envoy-ingress.nomad

# Check status
nomad job status envoy-ingress

# Get the node where it's running
nomad job status envoy-ingress | grep "Allocations"
nomad alloc status <allocation-id>
```

### 2. Deploy Whoami Application

```bash
# Deploy whoami with dynamic ports
nomad job run whoami.nomad

# Check status
nomad job status whoami
```

### 3. Verify Services are Registered in Consul

```bash
# Check Consul services
consul catalog services

# Get whoami service details
consul catalog service whoami

# Should show 2 instances with their IPs and ports
```

### 4. Test the Ingress

```bash
# From the Nomad server or any machine that can reach it
curl http://192.168.1.150:8080/

# Should return whoami response
```

### 5. Check Envoy Admin Interface

```bash
# View Envoy configuration and health
curl http://192.168.1.150:9901/config_dump
curl http://192.168.1.150:9901/clusters
```

## How Envoy Discovers Services

The Envoy ingress uses Nomad's **template** stanza with Consul:

1. Consul template queries Consul for services with name "whoami"
2. Template generates Envoy configuration with all service instances
3. When services scale up/down, template regenerates config
4. Envoy automatically reloads with new configuration

## Configuration

### Envoy Ingress

The `envoy-ingress.nomad` file contains:
- **Port 8080**: HTTP listener for incoming traffic
- **Port 9901**: Admin interface for monitoring
- **Consul template**: Auto-generates Envoy config from Consul services

To modify which services Envoy routes to, edit the template section in `envoy-ingress.nomad`:

```hcl
{{ range service "whoami" }}  # Change "whoami" to your service name
```

### Whoami Service

The `whoami.nomad` uses:
- **Dynamic ports**: Nomad assigns available ports automatically
- **Consul registration**: Service registers with name "whoami"
- **Health checks**: Consul monitors service health

## Adding More Services

To add more services to the Envoy ingress:

### Option 1: Add to Existing Envoy Config

Edit `envoy-ingress.nomad` template section to add more clusters and routes:

```hcl
virtual_hosts:
- name: whoami_service
  domains: ["whoami.*", "*"]  # Add domain matching
  routes:
  - match:
      prefix: "/whoami"
    route:
      cluster: whoami_cluster
  - match:
      prefix: "/api"
    route:
      cluster: api_cluster

# Add more clusters
clusters:
- name: api_cluster
  # ... same as whoami_cluster but with service "api"
  {{ range service "api" }}
```

### Option 2: Use Dynamic Configuration

For more complex setups, consider using Envoy's CDS/EDS with Consul:

```bash
# Deploy a separate envoy-ingress-dynamic.nomad with CDS enabled
nomad job run envoy-ingress-dynamic.nomad
```

## Monitoring

### Check Envoy Status

```bash
# Get allocation ID
nomad job status envoy-ingress

# View logs
nomad alloc logs <allocation-id> envoy

# Check admin interface
curl http://192.168.1.150:9901/stats
curl http://192.168.1.150:9901/clusters
```

### Check Service Discovery

```bash
# Verify Consul has services
consul catalog service whoami

# Should output all whoami instances with IPs and ports
```

## Troubleshooting

### Issue: "Connection refused on port 8080"

**Check 1**: Is Envoy ingress running?
```bash
nomad job status envoy-ingress
```

**Check 2**: What node is it on?
```bash
nomad alloc status <alloc-id> | grep "Node Name"
nomad node status <node-name> -verbose | grep "Node Address"
```

**Check 3**: Update your external Envoy `.env` with the correct IP:
```env
NOMAD_CLUSTER_IP=<actual-node-ip>
NOMAD_CLUSTER_PORT=8080
```

### Issue: "No healthy upstream"

**Cause**: Envoy can't find any whoami instances

**Fix**:
```bash
# Check if whoami is registered in Consul
consul catalog service whoami

# If empty, check whoami job
nomad job status whoami
nomad alloc status <alloc-id>

# Check allocation logs
nomad alloc logs <alloc-id>
```

### Issue: "Template rendering failed"

**Cause**: Consul template can't connect to Consul

**Fix**:
```bash
# Check Nomad-Consul integration
nomad agent-info | grep consul

# Restart the envoy-ingress job
nomad job restart envoy-ingress
```

### Issue: "Port 8080 already in use"

**Cause**: Another service is using port 8080

**Fix**: Change the static port in `envoy-ingress.nomad`:
```hcl
port "http" {
  static = 8081  # Change to available port
  to     = 8080
}
```

Then update external Envoy `.env`:
```env
NOMAD_CLUSTER_PORT=8081
```

## Update External Envoy Proxy

Your external Envoy proxy should point to the Nomad node running envoy-ingress:

1. **Find the node IP where envoy-ingress is running:**
   ```bash
   nomad job status envoy-ingress
   nomad alloc status <alloc-id> | grep "Node Name"
   # Get the IP of that node
   ```

2. **Update `envoy/.env`:**
   ```env
   NOMAD_CLUSTER_IP=192.168.1.150  # IP of the node running envoy-ingress
   NOMAD_CLUSTER_PORT=8080
   ```

3. **Regenerate external Envoy config:**
   ```bash
   cd ../../envoy
   ./generate-envoy-config.sh
   docker compose restart envoy
   ```

## Cleanup

```bash
# Stop whoami
nomad job stop whoami

# Stop Envoy ingress
nomad job stop envoy-ingress

# Purge from history
nomad job stop -purge whoami
nomad job stop -purge envoy-ingress
```

## Advanced: Multiple Routes

For complex routing scenarios, you can extend the Envoy template:

```hcl
template {
  data = <<EOF
# ... existing config ...
virtual_hosts:
- name: backend_services
  domains: ["*"]
  routes:
  # Route /whoami to whoami service
  - match:
      prefix: "/whoami"
    route:
      prefix_rewrite: "/"
      cluster: whoami_cluster
  # Route /api to api service  
  - match:
      prefix: "/api"
    route:
      prefix_rewrite: "/"
      cluster: api_cluster
  # Default route
  - match:
      prefix: "/"
    route:
      cluster: whoami_cluster

clusters:
- name: whoami_cluster
  # ...
{{ range service "whoami" }}
  # ...
{{ end }}

- name: api_cluster
  # ...
{{ range service "api" }}
  # ...
{{ end }}
EOF
}
```

This setup gives you a powerful, auto-scaling ingress controller for Nomad using Envoy!
