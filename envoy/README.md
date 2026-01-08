# Envoy Proxy with Automated SSL Certificates

This setup deploys Envoy Proxy with automated Let's Encrypt SSL certificate generation and renewal using Certbot with Google Cloud DNS.

## Features

- **Envoy Proxy**: High-performance edge proxy
- **Multi-domain support**: Configure multiple domains via .env file
- **Automated SSL**: Certbot with DNS-01 challenge via Google Cloud DNS
- **Auto-renewal**: Certificates renew automatically every 12 hours (when needed)
- **HTTP to HTTPS redirect**: All HTTP traffic is redirected to HTTPS
- **Zero-downtime reload**: Certificates are hot-reloaded when updated

## Prerequisites

1. **GCP Service Account** with DNS admin permissions:
   - Go to GCP Console → IAM & Admin → Service Accounts
   - Create a service account with "DNS Administrator" role
   - Create and download JSON key

2. **DNS Setup**:
   - Your domains must be managed in Google Cloud DNS
   - Point your router's port forwarding: 80 → this host:80, 443 → this host:443

3. **Kubernetes Setup**:
   - K8s cluster accessible at the configured IP (default: 192.168.1.200)
   - Services deployed and accessible

## Setup Instructions

### 1. Configure Environment Variables

```cmd
REM Copy the example file
copy .env.example .env

REM Edit .env and set your domains (comma-separated for multiple domains)
REM Example: DOMAINS=whoami.ope.apps.technovateit-solutions.com,api.ope.apps.technovateit-solutions.com
```

**Example .env:**
```env
DOMAINS=whoami.ope.apps.technovateit-solutions.com,api.ope.apps.technovateit-solutions.com
LETSENCRYPT_EMAIL=admin@technovateit-solutions.com
K8S_CLUSTER_IP=192.168.1.200
GCP_CREDENTIALS_PATH=./gcp-credentials.json
GCP_CREDENTIALS_CONTAINER_PATH=/gcp-credentials.json
```

### 2. Configure GCP Credentials

```cmd
REM Copy the example file
copy gcp-credentials.json.example gcp-credentials.json

REM Edit with your actual GCP service account credentials
REM Make sure the service account has DNS Administrator role
```

### 3. Generate Envoy Configuration

**Windows:**
```cmd
generate-envoy-config.bat
```

**Linux/WSL/Mac:**
```bash
chmod +x generate-envoy-config.sh
./generate-envoy-config.sh
```

> **Note for WSL/Linux users**: The script automatically handles Windows line endings (CRLF) in the `.env` file.

### 4. Create Required Directories

**Windows:**
```cmd
mkdir certs
mkdir certbot-logs
mkdir logs
```

**Linux/WSL/Mac:**
```bash
mkdir -p certs certbot-logs logs
```

### 5. Start the Services

```bash
# First time - will request certificates
docker-compose up -d

# Check logs
docker-compose logs -f certbot
docker-compose logs -f envoy
```

### 6. Update K8s Ingress for Your Services

Update your Kubernetes HTTPRoute/Ingress to accept the new domains. For whoami service:

```yaml
hostnames:
- "whoami.local"
- "whoami.ope.apps.technovateit-solutions.com"
```

## Adding More Domains

To add more domains:

1. **Update .env file:**
   ```env
   DOMAINS=whoami.ope.apps.technovateit-solutions.com,api.ope.apps.technovateit-solutions.com,dashboard.ope.apps.technovateit-solutions.com
   ```

2. **Regenerate Envoy configuration:**
   ```bash
   # Windows
   generate-envoy-config.bat
   
   # Linux/WSL/Mac
   ./generate-envoy-config.sh
   ```

3. **Recreate the containers:**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

4. **Update K8s ingress** to accept the new domains

The certbot service will automatically request a certificate that covers all domains in a single certificate.

## Architecture

```
Internet
   ↓
Router (Port Forward 80, 443)
   ↓
Envoy Proxy (This Docker Compose)
   ├─ Port 80  → Redirect to 443
   └─ Port 443 → SSL Termination → Forward to K8s
       ↓
   K8s Cluster
       └─ Envoy Gateway/Ingress → Your Services
```

## Services

### Envoy Proxy
- **Ports**: 80 (HTTP), 443 (HTTPS), 9901 (Admin)
- **Config**: `envoy.yaml` (generated from .env)
- **Logs**: `./logs/access.log`

### Certbot
- **Purpose**: Request and renew SSL certificates
- **Provider**: Google Cloud DNS
- **Renewal**: Every 12 hours (only renews when <30 days remain)
- **Multi-domain**: All domains in DOMAINS variable are included in one certificate

### Cert Reloader
- **Purpose**: Detect certificate changes and reload Envoy
- **Method**: Sends SIGHUP to Envoy for graceful reload

## Monitoring

### Check Certificate Status
```bash
docker-compose exec certbot certbot certificates
```

### View Envoy Admin Interface
Open browser: `http://localhost:9901`

### Check Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f envoy
docker-compose logs -f certbot
```

## Troubleshooting

### Line Ending Issues (WSL/Linux)
If you see errors like `$'\r': command not found`, the `.env` file has Windows line endings. The `generate-envoy-config.sh` script automatically fixes this, but you can also manually convert:

```bash
# Using dos2unix
dos2unix .env

# Or using sed
sed -i 's/\r$//' .env
```

### Certificate Not Generated
```bash
# Check certbot logs
docker-compose logs certbot

# Common issues:
# - GCP credentials invalid
# - Service account lacks DNS permissions
# - Domains not in Google Cloud DNS
```

### Envoy Not Starting
```bash
# Check if certificates exist
ls -la certs/live/

# If missing, certbot hasn't run yet - wait or check certbot logs
```

### Connection to K8s Failing
```bash
# Test K8s connectivity
curl http://192.168.1.200

# Check Envoy admin
curl http://localhost:9901/clusters

# Verify K8s ingress accepts the domain
```

## Maintenance

### Force Certificate Renewal
```bash
docker-compose exec certbot certbot renew --force-renewal
```

### Update Envoy Configuration
```bash
# Edit .env
# Regenerate config
./generate-envoy-config.sh  # or generate-envoy-config.bat on Windows

# Restart
docker-compose restart envoy
```

## Security Notes

- Keep `gcp-credentials.json` secure and never commit to version control
- Keep `.env` secure and never commit to version control
- `.gitignore` is configured to exclude sensitive files
- Certificates are stored in `./certs` - backup regularly
- Consider using Docker secrets for production deployments

## Configuration Variables (.env)

All configuration is managed through the `.env` file:

| Variable | Description | Example |
|----------|-------------|---------|
| `DOMAINS` | Comma-separated list of domains to secure | `whoami.example.com,api.example.com` |
| `LETSENCRYPT_EMAIL` | Email for Let's Encrypt notifications | `admin@example.com` |
| `K8S_CLUSTER_IP` | IP address of your Kubernetes cluster | `192.168.1.200` |
| `GCP_CREDENTIALS_PATH` | Path to GCP service account JSON (host) | `./gcp-credentials.json` |
| `GCP_CREDENTIALS_CONTAINER_PATH` | Path inside certbot container | `/gcp-credentials.json` |

## Files

- `docker-compose.yml` - Main orchestration file
- `envoy.yaml` - Envoy proxy configuration (auto-generated, do not edit manually)
- `.env` - Configuration variables (you create this from .env.example)
- `.env.example` - Example configuration file
- `gcp-credentials.json` - GCP service account key (you create this)
- `gcp-credentials.json.example` - Example GCP credentials structure
- `generate-envoy-config.bat` - Windows script to generate envoy.yaml
- `generate-envoy-config.sh` - Linux/Mac script to generate envoy.yaml
- `.gitignore` - Prevents committing sensitive files
- `README.md` - This file
