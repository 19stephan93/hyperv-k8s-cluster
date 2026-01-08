# Whoami Application Deployment for Nomad
# This job deploys the whoami test application (traefik/whoami Docker image)
# Configured to work with Envoy ingress controller
# Note: "traefik/whoami" is just the Docker image name, not related to Traefik ingress

job "whoami" {
  datacenters = ["dc1"]
  type = "service"

  group "whoami" {
    count = 2

    network {
      port "http" {
        to = 80
      }
    }

    task "whoami" {
      driver = "docker"

      config {
        image = "traefik/whoami:latest"  # Simple HTTP test app (just happens to be published by Traefik team)
        ports = ["http"]
      }

      resources {
        cpu    = 100
        memory = 128
      }

      # Service registration with Consul (Envoy will discover from here)
      service {
        name = "whoami"
        port = "http"

        tags = [
          "whoami",
          "http",
        ]

        check {
          type     = "http"
          path     = "/"
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

    update {
      max_parallel     = 1
      min_healthy_time = "10s"
      healthy_deadline = "3m"
      auto_revert      = true
    }
  }
}
