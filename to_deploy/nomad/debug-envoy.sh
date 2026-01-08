#!/bin/bash

echo "=== Nomad Envoy Ingress Diagnostics ==="
echo ""

# Check Consul first
echo "0. Checking Consul connectivity..."
consul members 2>/dev/null
CONSUL_RUNNING=$?
if [ $CONSUL_RUNNING -ne 0 ]; then
    echo "WARNING: Cannot connect to Consul. Envoy template won't work without Consul!"
    echo "Is Consul running? Try: sudo systemctl status consul"
    echo ""
fi

# Check Envoy ingress status
echo "1. Checking Envoy ingress job status..."
nomad job status envoy-ingress 2>/dev/null
if [ $? -ne 0 ]; then
    echo "ERROR: Envoy ingress job not found or not running"
    echo "Deploy it with: nomad job run envoy-ingress.nomad"
    exit 1
fi

echo ""
echo "2. Getting Envoy ingress allocation..."
# Get allocation ID from the Allocations section, skip header line
ALLOC=$(nomad job status envoy-ingress 2>/dev/null | grep -A 100 "^Allocations" | grep "running" | head -1 | awk '{print $1}')

if [ -z "$ALLOC" ]; then
    echo "ERROR: No running Envoy ingress allocation found"
    echo "Check job status above for allocation status"
    exit 1
fi

echo "Allocation ID: $ALLOC"
echo ""

echo "3. Checking Envoy allocation details..."
nomad alloc status $ALLOC | head -20

echo ""
echo "4. Getting Node IP..."
# Get the node name
NODE_NAME=$(nomad alloc status $ALLOC | grep "^Node Name" | awk '{print $4}')
echo "Node Name: $NODE_NAME"

# Save the full allocation output for parsing
ALLOC_OUTPUT=$(nomad alloc status $ALLOC 2>/dev/null)

# Method 1: Extract from Allocation Addresses line - get everything before the arrow
NODE_ADDR=$(echo "$ALLOC_OUTPUT" | grep "8080.*->.*8080" | head -1 | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)

# Method 2: If that failed, try to find any valid IP in the output (excluding localhost)
if [ -z "$NODE_ADDR" ]; then
    echo "DEBUG: First method failed, trying fallback..."
    NODE_ADDR=$(echo "$ALLOC_OUTPUT" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v "127.0.0" | grep -v "0.0.0.0" | head -1)
fi

# Method 3: Try hostname resolution
if [ -z "$NODE_ADDR" ] && [ -n "$NODE_NAME" ]; then
    echo "DEBUG: Trying hostname resolution for $NODE_NAME..."
    NODE_ADDR=$(getent hosts "$NODE_NAME" | awk '{print $1}')
fi

# Method 4: Hardcode for hashicorp-client-1 as last resort (you can remove this later)
if [ -z "$NODE_ADDR" ] && [ "$NODE_NAME" = "hashicorp-client-1" ]; then
    echo "DEBUG: Using known IP for hashicorp-client-1..."
    NODE_ADDR="192.168.1.161"
fi

echo "Node Address: $NODE_ADDR"

echo ""
echo "5. Checking generated Envoy configuration..."
echo "Fetching envoy.yaml from allocation..."

# Try multiple paths for the envoy config file
ENVOY_CONFIG=""
for CONFIG_PATH in "envoy/local/envoy.yaml" "local/envoy.yaml" "alloc/data/local/envoy.yaml"; do
    ENVOY_CONFIG=$(nomad alloc fs $ALLOC "$CONFIG_PATH" 2>/dev/null)
    if [ -n "$ENVOY_CONFIG" ]; then
        echo "Found config at: $CONFIG_PATH"
        echo "$ENVOY_CONFIG"
        break
    fi
done

if [ -z "$ENVOY_CONFIG" ]; then
    echo ""
    echo "NOTE: Could not read envoy.yaml directly from allocation filesystem"
    echo "This is often normal - checking if Envoy is running with valid config..."

    # Check if Envoy is actually running and has loaded config
    if [ -n "$NODE_ADDR" ]; then
        CLUSTERS=$(curl -s -m 3 "http://$NODE_ADDR:9901/clusters" 2>/dev/null | head -20)
        if [ -n "$CLUSTERS" ]; then
            echo "✓ Envoy is running with loaded configuration"
            echo ""
            echo "Configured clusters (from admin API):"
            echo "$CLUSTERS"
        fi
    fi
fi

echo ""
echo "6. Checking Consul service registration for whoami..."
consul catalog services 2>/dev/null | grep -q whoami
CONSUL_STATUS=$?
if [ $CONSUL_STATUS -eq 0 ]; then
    echo "✓ Whoami service is registered in Consul"
    echo ""
    echo "Service instances:"
    # Use curl to query Consul HTTP API directly for service details
    curl -s "http://127.0.0.1:8500/v1/catalog/service/whoami" 2>/dev/null | \
        python3 -c "import sys,json; data=json.load(sys.stdin); [print(f\"  - {s['Address']}:{s['ServicePort']}\") for s in data]" 2>/dev/null \
        || consul catalog nodes -service=whoami 2>/dev/null \
        || echo "Could not get service details"
else
    echo "✗ Whoami service NOT registered in Consul"
    if [ $CONSUL_RUNNING -eq 0 ]; then
        echo "Consul is running but whoami service is not registered"
        echo "This means Nomad-Consul integration is not working properly"
    fi
fi

echo ""
echo "7. Checking whoami job status..."
nomad job status whoami 2>/dev/null || echo "Whoami job not found. Deploy with: nomad job run whoami.nomad"

echo ""
echo "8. Checking Envoy allocation logs for errors..."
echo "--- Last 30 lines of stdout (look for template errors) ---"
nomad alloc logs -stdout $ALLOC 2>/dev/null | tail -30
echo ""
echo "--- Last 10 lines of stderr ---"
nomad alloc logs -stderr $ALLOC 2>/dev/null | tail -10

echo ""
echo "9. Testing connectivity..."
if [ -n "$NODE_ADDR" ]; then
    echo "Envoy HTTP should be at: http://$NODE_ADDR:8080/"
    echo "Envoy Admin should be at: http://$NODE_ADDR:9901/"
    echo ""
    echo "Testing admin interface..."
    ADMIN_TEST=$(curl -s -m 3 http://$NODE_ADDR:9901/stats 2>/dev/null | head -5)
    if [ -n "$ADMIN_TEST" ]; then
        echo "✓ Admin interface is reachable"
        echo "$ADMIN_TEST"
    else
        echo "✗ Could not reach admin interface"
    fi
    echo ""
    echo "Testing HTTP endpoint..."
    HTTP_RESPONSE=$(curl -s -m 3 -o /dev/null -w "%{http_code}" http://$NODE_ADDR:8080/ 2>/dev/null)
    if [ "$HTTP_RESPONSE" = "200" ]; then
        echo "✓ HTTP endpoint returned 200 OK"
        echo ""
        echo "Response body:"
        curl -s -m 3 http://$NODE_ADDR:8080/ 2>/dev/null
    else
        echo "HTTP response code: $HTTP_RESPONSE"
        curl -v -m 3 http://$NODE_ADDR:8080/ 2>&1 | head -30
    fi
else
    echo "Cannot test - node address not found"
fi

echo ""
echo "=== Diagnostics Complete ==="
echo ""

# Summary
echo "=== SUMMARY ==="
if [ $CONSUL_RUNNING -ne 0 ]; then
    echo "❌ CRITICAL: Consul is not accessible!"
    echo "   Fix: Make sure Consul is running and accessible"
    echo "   Check: sudo systemctl status consul"
    echo ""
elif [ $CONSUL_STATUS -ne 0 ]; then
    echo "⚠️  WARNING: Consul is running but whoami service not registered"
    echo "   This means Nomad-Consul integration is not working"
    echo "   Check Nomad configuration: consul { address = \"127.0.0.1:8500\" }"
    echo ""
fi

if [ -n "$NODE_ADDR" ]; then
    # Check if HTTP is actually working
    HTTP_CHECK=$(curl -s -m 3 -o /dev/null -w "%{http_code}" http://$NODE_ADDR:8080/ 2>/dev/null)
    if [ "$HTTP_CHECK" = "200" ]; then
        echo "✅ SUCCESS: Envoy ingress is fully operational at $NODE_ADDR:8080"
    else
        echo "⚠️  Envoy ingress found at: $NODE_ADDR:8080 but HTTP returned: $HTTP_CHECK"
    fi
    echo ""
    echo "Next steps:"
    if [ $CONSUL_STATUS -ne 0 ]; then
        echo "1. Fix Nomad-Consul integration (whoami services not registering)"
        echo "   Check: nomad agent-info | grep consul"
        echo "   Ensure Nomad config has: consul { address = \"127.0.0.1:8500\" }"
    fi
    echo "2. Update your external Envoy .env with: NOMAD_CLUSTER_IP=$NODE_ADDR"
    echo "3. Regenerate external Envoy config: cd ../../envoy && ./generate-envoy-config.sh"
    echo "4. Restart external Envoy: docker compose restart envoy"
else
    echo "❌ Could not determine node address"
    echo "   Manually check: nomad alloc status $ALLOC"
fi
