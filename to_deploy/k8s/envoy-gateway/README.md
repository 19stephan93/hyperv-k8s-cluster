# Envoy Gateway Setup for K8s Cluster

This directory contains the configuration for Envoy Gateway as the ingress controller for the Kubernetes cluster.

## Architecture

- **Envoy Gateway**: Modern ingress controller based on Envoy Proxy
- **Gateway API**: Uses the Kubernetes Gateway API (successor to Ingress API)
- **MetalLB Integration**: Gateway service gets an IP from MetalLB pool
- **HTTP Only**: Configured for HTTP traffic (SSL termination handled by external Envoy)

## Installation Steps

### 1. Install Envoy Gateway

```bash
# Install the latest version of Envoy Gateway
kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/v1.0.0/install.yaml

# Verify installation
kubectl get pods -n envoy-gateway-system
```

### 2. Create Gateway Instance

```bash
# Apply the gateway configuration
kubectl apply -f gateway.yml

# Verify gateway is ready
kubectl get gateway -n envoy-gateway-system
kubectl get svc -n envoy-gateway-system
```

The Gateway will create a LoadBalancer service. MetalLB will assign it an IP from the configured pool (192.168.1.200-192.168.1.250).

### 3. Get Gateway IP

```bash
# Get the external IP assigned by MetalLB
kubectl get svc -n envoy-gateway-system

# Or specifically:
kubectl get gateway eg -n envoy-gateway-system -o jsonpath='{.status.addresses[0].value}'
```

## Usage

Applications use **HTTPRoute** resources instead of Ingress resources:

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
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: my-service
      port: 80
```

## Integration with External Envoy

The external Envoy proxy will:
1. Terminate SSL/TLS
2. Route traffic based on hostname/path to either K8s or Nomad
3. Forward HTTP traffic to this Gateway's LoadBalancer IP

Example external Envoy routing:
- `*.k8s.example.com` → K8s Gateway IP (from MetalLB)
- `*.nomad.example.com` → Nomad Consul Ingress Gateway

## Notes

- Gateway API is more flexible and powerful than the Ingress API
- HTTPRoute supports advanced routing (headers, query params, weighted routing)
- All Envoy configuration is done via Gateway API resources
- No custom annotations needed like with Traefik

