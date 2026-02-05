sub surrogate_keys {

set beresp.http.surrogate-key = req.url.basename;

  # Match last segment: 
  if (req.url.path ~ "^.*/([^/]+)$") {
    # re.group.1 = full-path
    set beresp.http.Surrogate-Key = re.group.1;
  }

  # Match last two segments: y and z
  if (req.url.path ~ "^.*/([^/]+)/([^/]+)$") {
  if (std.strstr(beresp.http.Surrogate-Key, re.group.1)) {
      # Do nothing. Accounts for shielding.
    }
    else 
    {
           if (!re.group.2) { goto surrogate_1; }

      surrogate_2: set beresp.http.Surrogate-Key = beresp.http.Surrogate-Key " " re.group.2;
      surrogate_1: set beresp.http.Surrogate-Key = beresp.http.Surrogate-Key " " re.group.1;
    
    
    } 
  }
}