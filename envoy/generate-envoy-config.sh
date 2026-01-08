#!/bin/bash

# Script to generate Envoy configuration based on .env file
# Usage: ./generate-envoy-config.sh

# Source the .env file
if [ ! -f .env ]; then
    echo "Error: .env file not found. Copy .env.example to .env and configure it."
    exit 1
fi

# Convert Windows line endings to Unix (handles CRLF issue)
sed -i 's/\r$//' .env 2>/dev/null || sed -i '' 's/\r$//' .env 2>/dev/null

source .env

# Combine all domains for certificate request
ALL_DOMAINS="${DOMAINS_K8S_SSL_TERMINATION},${DOMAINS_NOMAD_SSL_TERMINATION},${DOMAINS_K8S_SSL_PASSTHROUGH},${DOMAINS_NOMAD_SSL_PASSTHROUGH}"
# Remove trailing/leading commas and clean up
ALL_DOMAINS=$(echo "$ALL_DOMAINS" | sed 's/^,//;s/,$//;s/,,*/,/g')

# Get the first domain for certificate path
FIRST_DOMAIN=$(echo "$ALL_DOMAINS" | cut -d',' -f1 | xargs)

# Build virtual hosts for SSL termination domains
VIRTUAL_HOSTS=""

# Add K8s SSL termination domains
if [ -n "$DOMAINS_K8S_SSL_TERMINATION" ]; then
    IFS=',' read -ra TERM_ARRAY <<< "$DOMAINS_K8S_SSL_TERMINATION"
    for domain in "${TERM_ARRAY[@]}"; do
        domain=$(echo "$domain" | xargs)  # trim whitespace
        if [ -n "$domain" ]; then
            VIRTUAL_HOSTS="${VIRTUAL_HOSTS}
            - name: ${domain//./_}
              domains:
              - \"$domain\"
              routes:
              - match:
                  prefix: \"/\"
                route:
                  cluster: k8s_cluster
                  timeout: 30s"
        fi
    done
fi

# Add Nomad SSL termination domains
if [ -n "$DOMAINS_NOMAD_SSL_TERMINATION" ]; then
    IFS=',' read -ra TERM_ARRAY <<< "$DOMAINS_NOMAD_SSL_TERMINATION"
    for domain in "${TERM_ARRAY[@]}"; do
        domain=$(echo "$domain" | xargs)  # trim whitespace
        if [ -n "$domain" ]; then
            VIRTUAL_HOSTS="${VIRTUAL_HOSTS}
            - name: ${domain//./_}
              domains:
              - \"$domain\"
              routes:
              - match:
                  prefix: \"/\"
                route:
                  cluster: nomad_cluster
                  timeout: 30s"
        fi
    done
fi

# Generate envoy.yaml
cat > envoy.yaml << 'EOF'
admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901

static_resources:
  listeners:
  # HTTP Listener - Redirects all traffic to HTTPS
  - name: http_listener
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 80
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          codec_type: AUTO
          route_config:
            name: local_route
            virtual_hosts:
            - name: http_redirect
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                redirect:
                  https_redirect: true
                  response_code: MOVED_PERMANENTLY
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  # HTTPS Listener - Mixed: SSL termination + SSL passthrough
  - name: https_listener
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 443
    listener_filters:
    - name: envoy.filters.listener.tls_inspector
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.filters.listener.tls_inspector.v3.TlsInspector
    filter_chains:
EOF

# Add K8s SSL passthrough filter chains
if [ -n "$DOMAINS_K8S_SSL_PASSTHROUGH" ]; then
    IFS=',' read -ra PASS_ARRAY <<< "$DOMAINS_K8S_SSL_PASSTHROUGH"
    for domain in "${PASS_ARRAY[@]}"; do
        domain=$(echo "$domain" | xargs)
        if [ -n "$domain" ]; then
            cat >> envoy.yaml << EOF
    # Filter chain for $domain - SSL passthrough to K8s (no termination)
    - filter_chain_match:
        server_names:
        - "$domain"
      filters:
      - name: envoy.filters.network.tcp_proxy
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.tcp_proxy.v3.TcpProxy
          stat_prefix: ${domain//./_}_passthrough
          cluster: k8s_cluster_https
EOF
        fi
    done
fi

# Add Nomad SSL passthrough filter chains
if [ -n "$DOMAINS_NOMAD_SSL_PASSTHROUGH" ]; then
    IFS=',' read -ra PASS_ARRAY <<< "$DOMAINS_NOMAD_SSL_PASSTHROUGH"
    for domain in "${PASS_ARRAY[@]}"; do
        domain=$(echo "$domain" | xargs)
        if [ -n "$domain" ]; then
            cat >> envoy.yaml << EOF
    # Filter chain for $domain - SSL passthrough to Nomad (no termination)
    - filter_chain_match:
        server_names:
        - "$domain"
      filters:
      - name: envoy.filters.network.tcp_proxy
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.tcp_proxy.v3.TcpProxy
          stat_prefix: ${domain//./_}_passthrough
          cluster: nomad_cluster_https
EOF
        fi
    done
fi

# Add SSL termination filter chain
SSL_TERMINATION_DOMAINS="${DOMAINS_K8S_SSL_TERMINATION},${DOMAINS_NOMAD_SSL_TERMINATION}"
SSL_TERMINATION_DOMAINS=$(echo "$SSL_TERMINATION_DOMAINS" | sed 's/^,//;s/,$//;s/,,*/,/g')

if [ -n "$SSL_TERMINATION_DOMAINS" ]; then
    cat >> envoy.yaml << EOF
    # Filter chain for SSL termination domains
    - filter_chain_match:
        server_names:
EOF

    # Add all SSL termination domains to server_names
    IFS=',' read -ra TERM_ARRAY <<< "$SSL_TERMINATION_DOMAINS"
    for domain in "${TERM_ARRAY[@]}"; do
        domain=$(echo "$domain" | xargs)
        if [ -n "$domain" ]; then
            cat >> envoy.yaml << EOF
        - "$domain"
EOF
        fi
    done

    cat >> envoy.yaml << EOF
      filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_https
          codec_type: AUTO
          route_config:
            name: https_route
            virtual_hosts:${VIRTUAL_HOSTS}
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          access_log:
          - name: envoy.access_loggers.file
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.file.v3.FileAccessLog
              path: /var/log/envoy/access.log
      transport_socket:
        name: envoy.transport_sockets.tls
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext
          common_tls_context:
            tls_certificates:
            - certificate_chain:
                filename: /etc/letsencrypt/live/${FIRST_DOMAIN}/fullchain.pem
              private_key:
                filename: /etc/letsencrypt/live/${FIRST_DOMAIN}/privkey.pem
EOF
fi

cat >> envoy.yaml << EOF

  clusters:
  # Cluster for HTTP backend (SSL termination traffic to K8s)
  - name: k8s_cluster
    connect_timeout: 5s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: k8s_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: ${K8S_CLUSTER_IP}
                port_value: 80
    health_checks:
    - timeout: 5s
      interval: 10s
      unhealthy_threshold: 3
      healthy_threshold: 2
      http_health_check:
        path: "/"
        expected_statuses:
        - start: 200
          end: 404

  # Cluster for HTTPS backend (SSL passthrough traffic to K8s)
  - name: k8s_cluster_https
    connect_timeout: 5s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: k8s_cluster_https
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: ${K8S_CLUSTER_IP}
                port_value: 443

  # Cluster for Nomad backend (via Traefik or direct service)
  - name: nomad_cluster
    connect_timeout: 5s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: nomad_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: ${NOMAD_CLUSTER_IP}
                port_value: ${NOMAD_CLUSTER_PORT}
    health_checks:
    - timeout: 5s
      interval: 10s
      unhealthy_threshold: 3
      healthy_threshold: 2
      http_health_check:
        path: "/"
        expected_statuses:
        - start: 200
          end: 404

  # Cluster for HTTPS Nomad backend (SSL passthrough traffic to Nomad)
  - name: nomad_cluster_https
    connect_timeout: 5s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: nomad_cluster_https
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: ${NOMAD_CLUSTER_IP}
                port_value: 443
EOF

echo "✓ envoy.yaml generated successfully"
echo "✓ All domains for certificates: $ALL_DOMAINS"
echo "✓ K8s SSL Termination: $DOMAINS_K8S_SSL_TERMINATION"
echo "✓ K8s SSL Passthrough: $DOMAINS_K8S_SSL_PASSTHROUGH"
echo "✓ Nomad SSL Termination: $DOMAINS_NOMAD_SSL_TERMINATION"
echo "✓ Nomad SSL Passthrough: $DOMAINS_NOMAD_SSL_PASSTHROUGH"
echo "✓ Using K8s cluster: $K8S_CLUSTER_IP"
echo "✓ Using Nomad cluster: $NOMAD_CLUSTER_IP:$NOMAD_CLUSTER_PORT"
