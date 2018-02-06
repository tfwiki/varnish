vcl 4.0;
# set default backend if no server cluster specified
backend default {
    .host = "%BACKEND_HOST%";
    .port = "%BACKEND_PORT%";
}

# vcl_recv is called whenever a request is received 
sub vcl_recv {
        # Block external access to server-status
        if (req.url ~ "^/+?server-status") {
            return(synth(404,"Page not found"));
        }

        # Serve objects up to 2 minutes past their expiry if the backend
        # is slow to respond.
        # set req.grace = 120s;
        
        # We have a load balancer sitting in front of Varnish, so don't overwrite
        # any existing X-Forwarded-For header.
        if (!req.http.X-Forwarded-For) {
            set req.http.X-Forwarded-For = client.ip;
        }
        
        set req.backend_hint= default;
 
        # This uses the ACL action called "purge". Basically if a request to
        # PURGE the cache comes from anywhere other than localhost, ignore it.
        if (req.method == "PURGE") {
            return (purge);
        }
 
        # Pass any requests that Varnish does not understand straight to the backend.
        if (req.method != "GET" && req.method != "HEAD" &&
            req.method != "PUT" && req.method != "POST" &&
            req.method != "TRACE" && req.method != "OPTIONS" &&
            req.method != "DELETE") {
                return (pipe);
        } /* Non-RFC2616 or CONNECT which is weird. */
 
        # Pass anything other than GET and HEAD directly.
        if (req.method != "GET" && req.method != "HEAD") {
            return (pass);
        }      /* We only deal with GET and HEAD by default */
 
        # Pass requests from logged-in users directly.
        # Only detect cookies with "session" and "Token" in file name, otherwise nothing get cached.
        if (req.http.Authorization || req.http.Cookie ~ "session" || req.http.Cookie ~ "Token") {
            return (pass);
        } /* Not cacheable by default */
 
        # Pass any requests with the "If-None-Match" header directly.
        if (req.http.If-None-Match) {
            return (pass);
        }
 
        # Force lookup if the request is a no-cache request from the client.
        if (req.http.Cache-Control ~ "no-cache") {
            ban(req.url);
        }
 
        # normalize Accept-Encoding to reduce vary
        if (req.http.Accept-Encoding) {
          if (req.http.User-Agent ~ "MSIE 6") {
            unset req.http.Accept-Encoding;
          } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
          } elsif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
          } else {
            unset req.http.Accept-Encoding;
          }
        }
 
        return (hash);
}

sub vcl_pipe {
        # Note that only the first request to the backend will have
        # X-Forwarded-For set.  If you use X-Forwarded-For and want to
        # have it set for all requests, make sure to have:
        # set req.http.connection = "close";
 
        # This is otherwise not necessary if you do not do any request rewriting.
 
        set req.http.connection = "close";
}

# Called if the cache has a copy of the page.
sub vcl_hit {
        if (req.method == "PURGE") {
            ban(req.url);
            return (synth(200, "Purged"));
        }
 
        if (!obj.ttl > 0s) {
            return (pass);
        }
}
 
# Called if the cache does not have a copy of the page.
sub vcl_miss {
        if (req.method == "PURGE")  {
            return (synth(200, "Not in cache"));
        }
}

# Called after a document has been successfully retrieved from the backend.
sub vcl_backend_response {
        # set minimum timeouts to auto-discard stored objects
        set beresp.grace = 120s;
 
        if (beresp.ttl < 48h) {
          set beresp.ttl = 48h;
        }
 
        if (!beresp.ttl > 0s) {
          set beresp.uncacheable = true;
          return (deliver);
        }
 
        if (beresp.http.Set-Cookie) {
          set beresp.uncacheable = true;
          return (deliver);
        }
 
       if (beresp.http.Cache-Control ~ "(private|no-cache|no-store)") {
          set beresp.uncacheable = true;
          return (deliver);
        }
 
        if (beresp.http.Authorization && !beresp.http.Cache-Control ~ "public") {
          set beresp.uncacheable = true;
          return (deliver);
        }

        return (deliver);
}

sub vcl_deliver {
    if (obj.hits > 0) { # Add debug header to see if it's a HIT/MISS and the number of hits, disable when not needed
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
    # Please note that obj.hits behaviour changed in 4.0, now it counts per objecthead, not per object
    # and obj.hits may not be reset in some cases where bans are in use. See bug 1492 for details.
    # So take hits with a grain of salt
    set resp.http.X-Cache-Hits = obj.hits;
    
    return (deliver);
}