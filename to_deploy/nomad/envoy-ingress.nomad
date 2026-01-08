# Envoy Ingress Controller for Nomad
# This job runs Envoy as an ingress controller that discovers services from Consul

job "envoy-ingress" {
  datacenters = ["dc1"]
  type = "service"  # Changed from "system" to "service" for single instance

  group "envoy" {
    count = 1

    network {
      port "http" {
        static = 8080
        to     = 8080
      }
      port "admin" {
        static = 9901
        to     = 9901
      }
    }

    task "envoy" {
      driver = "docker"

      config {
        image = "envoyproxy/envoy:v1.28-latest"
        ports = ["http", "admin"]

        volumes = [
          "local/envoy.yaml:/etc/envoy/envoy.yaml"
        ]
      }

      # Generate Envoy configuration from template
      template {
        data = <<EOF
admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901

static_resources:
  listeners:
  - name: http_listener
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 8080
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
            - name: whoami_service
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: whoami_cluster
                  timeout: 30s
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
  - name: whoami_cluster
    connect_timeout: 5s
    type: STRICT_DNS
    dns_lookup_family: V4_ONLY
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: whoami_cluster
      endpoints:
      - lb_endpoints:
{{- range service "whoami" }}
        - endpoint:
            address:
              socket_address:
                address: {{ .Address }}
                port_value: {{ .Port }}
{{- else }}
        # No whoami services found - using dummy endpoint to prevent Envoy from failing
        - endpoint:
            address:
              socket_address:
                address: 127.0.0.1
                port_value: 1
{{- end }}
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
EOF
        destination = "local/envoy.yaml"
        change_mode = "signal"
        change_signal = "SIGHUP"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "envoy-ingress"
        port = "http"

        tags = [
          "ingress",
          "envoy",
        ]

        check {
          type     = "http"
          path     = "/ready"
          port     = "admin"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    restart {
      attempts = 3
      delay    = "15s"
      interval = "30m"
      mode     = "fail"
    }
  }
}
