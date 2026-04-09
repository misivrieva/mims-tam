terraform {
  required_providers {
    fastly = {
      source  = "fastly/fastly"
      version = ">= 8.6.0"
    }
  }
}

variable "mydict_geo" {
  type = string
  default = "basic_geofencing"
}

# Configure the Fastly Provider
provider "fastly" {
  api_key = "HF0vQUudT2A7vrIgO2FOalJmJBit1GNI"
}

resource "fastly_domain_v1" "mims_domain" {
    fqdn = "www.mimsjustdoit.co.uk"
    service_id = fastly_service_vcl.mims_tam.id
    #service_id = "fb2A8UG0gGgu6SqVkjwOCt"
    description = "This is my test domain."
}

# Create a Service
  resource "fastly_service_vcl" "mims_tam" {
    name = "mims_tam_website"

    backend {
      name                  = "aws"
      address               = "mims-ce-demo-site.s3.eu-north-1.amazonaws.com"
      port                  = 443
      use_ssl               = true
      ssl_cert_hostname     = "mims-ce-demo-site.s3.eu-north-1.amazonaws.com"
      ssl_sni_hostname      = "mims-ce-demo-site.s3.eu-north-1.amazonaws.com"
      ssl_check_cert        = true
      override_host         = "mims-ce-demo-site.s3.eu-north-1.amazonaws.com"
      max_conn              = 200
      connect_timeout       = 1000
      first_byte_timeout    = 15000
      between_bytes_timeout = 10000
      auto_loadbalance      = false
      shield = "lga-ny-us"

    }

     healthcheck {
      host = "mims-ce-demo-site.s3.eu-north-1.amazonaws.com"
       name = "healthcheck for aws"
       path = "/healthcheck.txt"
       check_interval = 10000
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
      shield                = "london-uk"
      request_condition     = "shield for GH"

    }

    condition {
      name      = "shield for GH"
      type      = "REQUEST"
      statement = "false"
      priority  = 10
  }
    condition {
      name = "shield for aws"
      type = "REQUEST"
      statement = "true"
      priority = 15
    }

    condition {
      name = "failover"
      type = "REQUEST"
      statement = "!req.backend.healthy"
      priority = 9
    }

    # condition {
    #   name = "URL after failover"
    #   type = "REQUEST"
    #   statement = "req.backend == F_github_pages"
    #   priority = 20
    # }

    # header {
    #   name = "URL rewrite"
    #   action = "set"
    #   type = "request"
    #   destination = "url"
    #   source = "\"/\""
    #   request_condition = "URL after failover"
    # }

    header {
      name        = "Backend Selection"
      action      = "set"
      type        = "request"
      destination = "backend"
      source      = "F_github_pages"
      request_condition = "failover"
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

    dictionary {
      name    =  var.mydict_geo
      write_only = false
    }
  }  

resource "fastly_service_dictionary_items" "items" {
  for_each = {
    for d in fastly_service_vcl.mims_tam.dictionary : d.name => d if d.name == var.mydict_geo
  }
  service_id = fastly_service_vcl.mims_tam.id
  dictionary_id = each.value.dictionary_id

  items = {
  }
}  

output "service_id" {
  value = fastly_service_vcl.mims_tam.id
}

output "active_version" {
  value = fastly_service_vcl.mims_tam.active_version
}
