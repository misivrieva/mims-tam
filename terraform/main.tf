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
      name = "mims-tam-test.global.ssl.fastly.net"
  }

    backend {
      name                  = "http_me"
      address               = "http-me.glitch.me"
      port                  = 443
      use_ssl               = true
      ssl_cert_hostname     = "http-me.glitch.me"
      ssl_sni_hostname      = "http-me.glitch.me"
      ssl_check_cert        = true
      override_host         = "http-me.glitch.me"
      max_conn              = 200
      connect_timeout       = 1000
      first_byte_timeout    = 15000
      between_bytes_timeout = 10000
      auto_loadbalance      = false
      shield = "lga-ny-us"

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
      shield = "london-uk"

    }

    force_destroy = false

    logging_syslog {
    name               = "local_logging"
    address            = "51.148.190.212"  # my IP
    port               = 514           # standard syslog port
    format             = "%h %l %u %t \"%r\" %>s %b"
    format_version     = 2
    message_type       = "classic"
    response_condition = ""  # log all requests
    }

    vcl {
      name    = "my_main_vcl"
      content = file("${path.module}/main.vcl")
      main    = true
    }

    vcl {
      name    = "surrogate_keys_vcl"
      content = file("${path.module}/surrogate_keys.vcl")
    }  

    dictionary {
      name    = "basic_geofencing" 
      write_only = false
    }
  }  

resource "fastly_service_dictionary_items" "items" {
  for_each = {
  for d in fastly_service_vcl.mims_tam.dictionary : d.name => d if d.name == "basic_geofencing"
  }
  service_id = fastly_service_vcl.mims_tam.id
  dictionary_id = each.value.dictionary_id

  items = {
    Germany: "block"
    France: "block"
  }
}  

output "service_id" {
  value = fastly_service_vcl.mims_tam.id
}

output "active_version" {
  value = fastly_service_vcl.mims_tam.active_version
}
