terraform {
  required_providers {
    fastly = {
      source  = "fastly/fastly"
      version = ">= 8.6.0"
    }
  }
}

# Configure the Fastly Provider
provider "fastly" {
  api_key = "HF0vQUudT2A7vrIgO2FOalJmJBit1GNI"
}

# Create a Service
resource "fastly_service_vcl" "mims_tam" {
  name = "mims_tam_website"

domain {
    name = "mimsjustdoit.co.uk"
  }

  domain {
    name = "www.mimsjustdoit.co.uk"
  }

  backend {
    address               = "misivrieva.github.io"
    name                  = "github_pages"
    port                  = 443
    use_ssl               = true
    ssl_cert_hostname     = "misivrieva.github.io"
    ssl_sni_hostname      = "misivrieva.github.io"
    ssl_check_cert        = true
    override_host         = "misivrieva.github.io"
    max_conn              = 200
    connect_timeout       = 1000
    first_byte_timeout    = 15000
    between_bytes_timeout = 10000
    auto_loadbalance      = false
  }

  force_destroy = true
}

output "service_id" {
  value = fastly_service_vcl.mims_tam.id
}

output "active_version" {
  value = fastly_service_vcl.mims_tam.active_version
}
