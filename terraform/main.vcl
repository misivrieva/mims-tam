sub vcl_recv { 
#FASTLY recv

  # Normally, you should consider requests other than GET and HEAD to be uncacheable
  # (to this we add the special FASTLYPURGE method)
  if (req.method != "HEAD" && req.method != "GET" && req.method != "FASTLYPURGE") {
    return(pass);
  }
  #default, go to bin 
  set req.backend = F_http_me;
  set req.http.host = "http-me.glitch.me";


  if (req.restarts == 0) {
  unset req.http.restarts;
  }

  if (req.restarts > 0) {
  # Ensure clustering runs on restart!
  set req.http.Fastly-Force-Shield = "1";
  set req.backend = F_github_pages;
  set req.http.restarts = req.restarts;
  return(lookup);
  }

  #basic_geofencing in action 

  # Check if the client's country is in the blocklist
  declare local var.country_status STRING;
  set var.country_status = table.lookup(country_blocklist, client.geo.country_name);
  
  if (var.country_status == "block") {
    error 403 "Access denied from your country";
  }


  return(lookup);
}

sub vcl_hash {
  set req.hash += req.url;
  set req.hash += req.http.host;
  #FASTLY hash
  return(hash);
}

sub vcl_hit {
#FASTLY hit
  return(deliver);
}

sub vcl_miss {
#FASTLY miss
if (req.restarts > 0) {
set bereq.http.host = "misivrieva.github.io";
}

  return(fetch);
}

sub vcl_pass {
#FASTLY pass
  return(pass);
}

sub vcl_fetch {
#FASTLY fetch

  # Unset headers that reduce cacheability for images processed using the Fastly image optimizer
  if (req.http.X-Fastly-Imageopto-Api) {
    unset beresp.http.Set-Cookie;
    unset beresp.http.Vary;
  }

  # Log the number of restarts for debugging purposes
  if (req.restarts > 0) {
    set beresp.http.Fastly-Restarts = req.restarts;
  }

  # If the response is setting a cookie, make sure it is not cached
  if (beresp.http.Set-Cookie) {
    return(pass);
  }

  # By default we set a TTL based on the `Cache-Control` header but we don't parse additional directives
  # like `private` and `no-store`. Private in particular should be respected at the edge:
  if (beresp.http.Cache-Control ~ "(?:private|no-store)") {
    return(pass);
  }

  # Do not cache anything but static assets
  if (beresp.http.Cache-Control !~"(?:s-maxage|max-age)" && req.url != "/graphql" && (req.url ~ "(?i)(css|js|gif|jpg|jpeg|bmp|png|ico|img|tga|webp|wmf|mp4)$")) {
  return (pass);
}

  # If no TTL has been provided in the response headers, set a default
  if (!beresp.http.Expires &&
    !(beresp.http.Surrogate-Control ~ "max-age") &&
    !(beresp.http.Cache-Control ~ "(?:s-maxage|max-age)") ) { {
    set beresp.ttl = 3600s;

    # Apply a longer default TTL for images processed using Image Optimizer
    if (req.http.X-Fastly-Imageopto-Api) {
      set beresp.ttl = 2592000s; # 30 days
      set beresp.http.Cache-Control = "max-age=2592000, public";
    }
  }
  if (beresp.status >= 500 && beresp.status < 600) {
    if (stale.exists) {
    return(deliver_stale);
    }
  }   

call surrogate_keys;
return(deliver);
}


sub vcl_error {
#FASTLY error

if (obj.status == 403 && obj.response == "Access denied from your country") {
    set obj.http.Content-Type = "text/html; charset=utf-8";
    synthetic {"
      <!DOCTYPE html>
      <html>
      <head><title>Access Denied</title></head>
      <body>
        <h1>403 Forbidden</h1>
        <p>Access from your country is not allowed.</p>
      </body>
      </html>
    "};
    return(deliver);
  }
  
  return(deliver);
}

sub vcl_deliver {
#FASTLY deliver

#Some debug info:
if ( req.http.Fastly-Debug ) {
    set resp.http.X-VCL-Version = req.vcl.version;
    set resp.http.Log-Fastly-Request:url = if(resp.http.Log-Fastly-Request:url, resp.http.Log-Fastly-Request:url " - ", "") resp.http.x-be-url;
    set resp.http.Log-Fastly-Request:method = if(resp.http.Log-Fastly-Request:method, resp.http.Log-Fastly-Request:method " - ", "") resp.http.x-be-method;
    set resp.http.Log-Fastly-Request:req_bknd = if(resp.http.Log-Fastly-Request:req_bknd, resp.http.Log-Fastly-Request:req_bknd " - ", "") resp.http.x-be-name;
}
unset resp.http.x-be-url;
unset resp.http.x-be-method;
unset resp.http.x-be-name;
set resp.http.X-Mims = "mims";
  return(deliver);
}

sub vcl_log {
  #FASTLY log
}

/* sub vcl_log {
#FASTLY log    

  set req.http.log-timing:log = time.elapsed.usec;

  declare local var.origin_ttfb FLOAT;
  declare local var.origin_ttlb FLOAT;

  if (fastly_info.state ~ "^(MISS|PASS)") {
    set var.origin_ttfb = std.atof(req.http.log-timing:fetch);
    set var.origin_ttfb -= std.atof(req.http.log-timing:misspass);

    if (req.http.log-timing:do_stream == "1") {
      set var.origin_ttlb = std.atof(req.http.log-timing:log);
      set var.origin_ttlb -= std.atof(req.http.log-timing:misspass);
    } else {
      set var.origin_ttlb = std.atof(req.http.log-timing:deliver);
      set var.origin_ttlb -= std.atof(req.http.log-timing:misspass);
    }
  } else {
    unset req.http.log-timing:conn_open_fetch;
    unset req.http.log-timing:conn_used_fetch;
  }

  set var.origin_ttfb /= 1000;
  set var.origin_ttlb /= 1000;

  declare local var.response_ttfb FLOAT;
  set var.response_ttfb = time.to_first_byte;
  set var.response_ttfb *= 1000;

  declare local var.response_ttlb FLOAT;
  set var.response_ttlb = std.atof(req.http.log-timing:log);
  set var.response_ttlb /= 1000;

  declare local var.client_tcpi_rtt INTEGER;
  set var.client_tcpi_rtt = client.socket.tcpi_rtt;
  set var.client_tcpi_rtt /= 1000;

  if (fastly_info.state !~ "^(MISS|PASS)") {
    unset req.http.log-origin:host;
    unset req.http.log-origin:ip;
    unset req.http.log-origin:method;
    unset req.http.log-origin:name;
    unset req.http.log-origin:port;
    unset req.http.log-origin:reason;
    unset req.http.log-origin:shield;
    unset req.http.log-origin:status;
    unset req.http.log-origin:url;
    set var.origin_ttfb = math.NAN;
    set var.origin_ttlb = math.NAN;
  }

  set req.http.log-client:tcpi_rtt = var.client_tcpi_rtt;
  set req.http.log-origin:ttfb = var.origin_ttfb;
  set req.http.log-origin:ttlb = var.origin_ttlb;
  set req.http.log-response:ttfb = var.response_ttfb;
  set req.http.log-response:ttlb = var.response_ttlb;

  log "syslog " req.service_id " syslog :: { "
      "\"timestamp\":\"" + json.escape(strftime({"%Y-%m-%dT%H:%M:%S"}, time.start) + ":" + time.start.usec_frac) + "Z\", "
      "\"client_as_number\":" + json.escape(client.as.number) + ", "
      "\"client_city\":\"" + json.escape(client.geo.city) + "\", "
      "\"client_congestion_algorithm\":\"" + json.escape(client.socket.congestion_algorithm) + "\", "
      "\"client_country_code\":\"" + json.escape(client.geo.country_code3) + "\", "
      "\"client_cwnd\":" + json.escape(client.socket.cwnd) + ", "
      "\"client_delivery_rate\":" + json.escape(client.socket.tcpi_delivery_rate) + ", "
      "\"client_ip\":\"" + json.escape(req.http.Fastly-Client-IP) + "\", "
      "\"client_ip_alt\":\"" + json.escape(client.ip) + "\", "
      "\"client_latitude\":" + json.escape(if(client.geo.latitude == 999.9, "null", client.geo.latitude)) + ", "
      "\"client_longitude\":" + json.escape(if(client.geo.longitude == 999.9, "null", client.geo.longitude)) + ", "
      "\"client_ploss\":" + json.escape(client.socket.ploss) + ", "
      "\"client_requests\":" + json.escape(client.requests) + ", "
      "\"client_retrans\":" + json.escape(client.socket.tcpi_delta_retrans) + ", "
      "\"client_rtt\":" + req.http.log-client:tcpi_rtt + ", "
      "\"fastly_is_edge\":" + json.escape(if(fastly.ff.visits_this_service == 0, "true", "false")) + ", "
      "\"fastly_is_shield\":" + json.escape(if(req.http.log-origin:shield == server.datacenter, "true", "false")) + ", "
      "\"fastly_pop\":\"" + json.escape(server.datacenter) + "\", "
      "\"fastly_server\":\"" + json.escape(server.hostname) + "\", "
      "\"fastly_shield_used\":" + if(req.http.log-origin:shield, "\"" req.http.log-origin:shield "\"", "null") + ", "
      "\"origin_host\":" + if(req.http.log-origin:host, "\"" + json.escape(req.http.log-origin:host) + "\"", "null") + ", "
      "\"origin_ip\":" + if(req.http.log-origin:ip, "\"" + json.escape(req.http.log-origin:ip) + "\"", "null") + ", "
      "\"origin_method\":" + if(req.http.log-origin:method, "\"" + json.escape(req.http.log-origin:method) + "\"", "null") + ", "
      "\"origin_name\":" + if(req.http.log-origin:name, "\"" + json.escape(req.http.log-origin:name) + "\"", "null") + ", "
      "\"origin_port\":" + if(req.http.log-origin:port, req.http.log-origin:port, "null") + ", "
      "\"origin_reason\":" + if(req.http.log-origin:reason, "\"" + json.escape(req.http.log-origin:reason) + "\"", "null") + ", "
      "\"origin_status\":" + if(req.http.log-origin:status, json.escape(req.http.log-origin:status), "null") + ", "
      "\"origin_ttfb\":" + if(req.http.log-origin:ttfb == "NaN", "null", req.http.log-origin:ttfb) + ", "
      "\"origin_ttlb\":" + if(req.http.log-origin:ttlb == "NaN", "null", req.http.log-origin:ttlb) + ", "
      "\"origin_url\":" + if(req.http.log-origin:url, "\"" + json.escape(req.http.log-origin:url) + "\"", "null") + ", "
      "\"request_host\":\"" + json.escape(req.http.log-request:host) + "\", "
      "\"request_is_h2\":\"" + json.escape(if(fastly_info.is_h2, "true", "false")) + "\", "
      "\"request_is_ipv6\":\"" + json.escape(if(req.is_ipv6, "true", "false")) + "\", "
      "\"request_method\":\"" + json.escape(req.http.log-request:method) + "\", "
      "\"request_referer\":" + if(req.http.referer, "\"" + json.escape(req.http.referer) + "\"", "null") + ", "
      "\"request_tls_version\":\"" + json.escape(if(tls.client.protocol, tls.client.protocol, "")) + "\", "
      "\"request_url\":\"" + json.escape(req.http.log-request:url) + "\", "
      "\"request_user_agent\":" + if(req.http.user-agent, "\"" + json.escape(req.http.user-agent) + "\"", "null") + ", "
      "\"response_age\":" + regsub(resp.http.Age, "\.000$", "") + ", "
      "\"response_bytes_body\":" + resp.body_bytes_written + ", "
      "\"response_bytes_header\":" + resp.header_bytes_written + ", "
      "\"response_bytes\":" + resp.bytes_written + ", "
      "\"response_cache_control\":" + if(resp.http.cache-control, "\"" + json.escape(resp.http.cache-control) + "\"", "null") + ", "
      "\"response_completed\":\"" + if(resp.completed, "true", "false") + "\", "
      "\"response_content_length\":" + if(resp.http.content-length, resp.http.content-length, "null") + ", "
      "\"response_content_type\":" + if(resp.http.content-type, "\"" + json.escape(resp.http.content-type) + "\"", "null") + ", "
      "\"response_reason\":" + if(resp.response, "\"" + json.escape(resp.response) + "\"", "null") + ", "
      "\"response_state\":\"" + fastly_info.state + "\", "
      "\"response_status\":" + resp.status + ", "
      "\"response_ttfb\":" + req.http.log-response:ttfb + ", "
      "\"response_ttl\":" + obj.ttl + ", "
      "\"response_ttlb\":" + req.http.log-response:ttlb
      " }"; */

}
