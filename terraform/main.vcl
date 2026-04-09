sub vcl_recv { 
#FASTLY recv

  # Normally, you should consider requests other than GET and HEAD to be uncacheable
  # (to this we add the special FASTLYPURGE method)
  if (req.method != "HEAD" && req.method != "GET" && req.method != "FASTLYPURGE") {
    return(pass);
  }
  #rewrite the url to account for s3 internals
  if (req.backend == F_aws && req.url == "/" ){
    set req.url = "/index-aws.html";
  }

  #fetch the laning page from GH

  if (req.backend == F_github_pages && req.url == "/" ){
    set req.url = "/mims-tam/index.html"; # double mims-tam
  }
  #basic_geofencing in action 

  # Check if the client's country is in the blocklist
  declare local var.country_status STRING;
  set var.country_status = table.lookup(basic_geofencing, client.geo.country_name);
  
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

if (req.backend == F_github_pages){
  set bereq.url = "/mims-tam" + req.url;
}

  return(fetch);
}

sub vcl_pass {
#FASTLY pass

if (req.backend == F_github_pages){
  set bereq.url = "/mims-tam" + req.url;
}
  return(pass);
}


sub vcl_fetch {
#FASTLY fetch
  set beresp.ttl = 5s;
  set beresp.http.Cache-Control = "max-age=5";

  call surrogate_keys;

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
    !(beresp.http.Cache-Control ~ "(?:s-maxage|max-age)") ) {
    set beresp.ttl = 3600s;

    # Apply a longer default TTL for images processed using Image Optimizer
    if (req.http.X-Fastly-Imageopto-Api) {
      set beresp.ttl = 2592000s; # 30 days
      set beresp.http.Cache-Control = "max-age=2592000, public";
    }
  }  


return(deliver);
}

sub vcl_log {
  #FASTLY log
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

sub surrogate_keys {

set beresp.http.Surrogate-key = regsub(req.url, "^/([^/]+).*", "\1");
set beresp.http.Surrogate-key = beresp.http.Surrogate-key + " " + regsub(req.url.basename, "([^\.]+)\..*", "\1");
}