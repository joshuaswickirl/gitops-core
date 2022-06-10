
package greymatter

import (
  greymatter "greymatter.io/api"
  rbac "envoyproxy.io/extensions/filters/http/rbac/v3"
  jwt_authn "envoyproxy.io/extensions/filters/http/jwt_authn/v3"
)

/////////////////////////////////////////////////////////////
// "Functions" for Grey Matter config objects with defaults
// representing an ingress to a local service. Override-able.
/////////////////////////////////////////////////////////////

#domain: greymatter.#Domain & {
  domain_key: string
  name: string | *"*"
  port: int | *defaults.ports.default_ingress
  zone_key: mesh.spec.zone
}

#listener: greymatter.#Listener & {
  _tcp_upstream?: string // for TCP listeners, you can just specify the upstream cluster
  _is_ingress: bool | *false // specifiy if this listener is for ingress which will active default HTTP filters
  _gm_observables_topic: string // unique topic name for observable audit collection
  _spire_self: string    // can specify current identity - defaults to "edge"
  _spire_other: string // can specify an allowable downstream identity - defaults to "edge"
  _enable_oidc_authentication: bool | *false 
  _enable_oidc_validation: bool | *false
  _enable_rbac: bool | *false
  _enable_jwt_authn: bool | *false


  listener_key: string
  name: listener_key
  ip: string | *"0.0.0.0"
  port: int | *defaults.ports.default_ingress
  domain_keys: [...string] | *[listener_key]

  // if there's a tcp cluster, 
  if _tcp_upstream != _|_ {
    active_network_filters: ["envoy.tcp_proxy"]
    network_filters: envoy_tcp_proxy: {
      cluster: _tcp_upstream // NB: contrary to the docs, this points at a cluster *name*, not a cluster_key
      stat_prefix: _tcp_upstream
    }
  }

  // if there isn't a tcp cluster, then assume http filters, and provide the usual defaults
  if _tcp_upstream == _|_ && _is_ingress == true {
    active_http_filters: [
      if _enable_oidc_authentication {
        "gm.oidc-authentication",
      }
      "gm.observables",
      if _enable_oidc_validation {
        "gm.oidc-validation",
      }
      if _enable_jwt_authn {
        "envoy.jwt_authn",
      }
      if _enable_rbac {
        "envoy.rbac",
      }
      "gm.metrics",
      ...string
    ] 
    http_filters: {
        //Important: If your filter is multiple words, make it a quoted field
	      //so that gm-control can pick up the configuration 
        gm_metrics: {
          metrics_host: "0.0.0.0" // TODO are we still scraping externally? If not, set this to 127.0.0.1
          metrics_port: 8081
          metrics_dashboard_uri_path: "/metrics"
          metrics_prometheus_uri_path: "prometheus" // TODO slash or no slash?
          metrics_ring_buffer_size: 4096
          prometheus_system_metrics_interval_seconds: 15
          metrics_key_function: "depth"
          metrics_key_depth: string | *"1"
          metrics_receiver: {
            redis_connection_string: string | *"redis://127.0.0.1:\(defaults.ports.redis_ingress)"
            push_interval_seconds: 10
          }
        }
        gm_observables: {
          topic: _gm_observables_topic
        }
      if _enable_oidc_authentication {
        "gm_oidc-authentication": {        
          provider: string | *""
          serviceUrl:   string | *""
          callbackPath: string | *""

          clientId: string | *""
          clientSecret: string | *""

          accessToken?: {
            location:  *"header" | _ // options are "header" | "cookie" | "queryString" | "metadata"
            if location == "metadata" {
              metadataFilter: string
            }
            key: string | *""
            if location == "cookie" {
              cookieOptions: {
                httpOnly: bool | *false
                secure: bool | *false
                maxAge: string | *""
                domain: string | *""
                path: string | *""
              }
            }
          }

          idToken?: {
            location: *"header" | _
            key: string | *""
            if location == "cookie" {
              cookieOptions: {
                httpOnly: bool | *false
                secure: bool | *false
                maxAge: string | *""
                domain: string | *""
                path: string | *""
              }
            }
          }

          tokenRefresh?: {
            enabled: bool |*false
            endpoint: string | *""
            realm: string | *""
            timeoutMs: int | *0
            useTLS: bool | *false
            if useTLS {
              certPath: string | *""
              keyPath: string | *""
              caPath: string | *""
              insecureSkipVerify: bool | *false
            }
          }

          // Optional requested permissions
          additionalScopes: [...string] | *[]
        }
      }
      if _enable_oidc_validation {
        "gm_oidc-validation": {
          enforce: bool | *false
          if enforce {
            enforceResponseCode: int32 | *403
          }
          accessToken?: {
            location: *"header" | _
            if location == "metadata"{
              metadataFilter: string 
            }
          }
          userInfo?: {
            location: *"header" | _
          }
          TLSConfig?: {
            useTLS: bool | *false
            certPath: string | *""
            keyPath: string | *""
            caPath: string | *""
            insecureSkipVerify: bool | *false
          }
        }
      }
      if _enable_rbac {
        envoy_rbac: #envoy_rbac_filter
      }
      if _enable_jwt_authn {
        "envoy_jwt-authn": #envoy_jwt_authn_filter
      }
    }
  }

  if config.spire && _spire_self != _|_ {
    secret: #spire_secret & {
      // Expects _name and _subject to be passed in like so from above:
      // _spire_self: "dashboard"
      // _spire_other: "edge"  // but this defaults to "edge" and may be omitted
      _name: _spire_self
      _subject: _spire_other
      // TODO I just copied the following two from the previous operator without knowing why -DC
      set_current_client_cert_details: uri: true 
      forward_client_cert_details: "APPEND_FORWARD"
    }
  }

  zone_key: mesh.spec.zone
  protocol: "http_auto" // vestigial
}

#cluster: greymatter.#Cluster & {
  // You can either specify the upstream with these, or leave it to service discovery
  _upstream_host: string | *"127.0.0.1"
  _upstream_port: int
  _spire_self: string    // can specify current identity - defaults to "edge"
  _spire_other: string // can specify an allowable upstream identity - defaults to "edge"
  _enable_circuit_breakers: bool | *false

  cluster_key: string
  name: string | *cluster_key
  instances: [...greymatter.#Instance] | *[]
  if _upstream_port != _|_ {
    instances: [{ host: _upstream_host, port: _upstream_port }]
  } 
  if config.spire && _spire_other != _|_ {
    require_tls: true
    secret: #spire_secret & {
      // Expects _name and _subject to be passed in like so from above:
      // _spire_self: "redis"  // but this defaults to "edge" and may be omitted
      // _spire_other: "dashboard"
      _name: _spire_self
      _subject: _spire_other
    }
  }
  zone_key: mesh.spec.zone
  
  if _enable_circuit_breakers {
    circuit_breakers: #circuit_breaker // can specify circuit breaker levels for normal
    // and high priority traffic with configured defaults
  }
}

#circuit_breaker: {
  #circuit_breaker_default
  high?: #circuit_breaker_default
}

#circuit_breaker_default: {
  max_connections:      int64 | *512
  max_pending_requests: int64 | *512
  max_requests:         int64 | *512
  max_retries:          int64 | *2
  max_connection_pools: int64 | *512
  track_remaining:      bool | *false
}

#route: greymatter.#Route & {
  route_key: string
  domain_key: string | *route_key
  _upstream_cluster_key: string | *route_key
  route_match: {
    path: string | *"/"
    match_type: string | *"prefix"
  }
  rules: [{
    constraints: light: [{
      cluster_key: _upstream_cluster_key
      weight: 1
    }]
  }]
  zone_key: mesh.spec.zone
  prefix_rewrite: string | *"/"
}

#proxy: greymatter.#Proxy & {
  proxy_key: string
  name: proxy_key
  domain_keys: [...string] | *[proxy_key] // TODO how to get more in here for, e.g., the extra egresses?
  listener_keys: [...string] | *[proxy_key]
  zone_key: mesh.spec.zone
}



#spire_secret: {
  _name:    string | *"edge" // at least one of these will be overridden
  _subject: string | *"edge"
  _subjects?: [...string] // If provided, this list of strings will be used instead of _subject

  set_current_client_cert_details?: {...}
  forward_client_cert_details?: string

  secret_validation_name: "spiffe://greymatter.io"
  secret_name:            "spiffe://greymatter.io/\(mesh.metadata.name).\(_name)"
  if _subjects == _|_ {
    subject_names: ["spiffe://greymatter.io/\(mesh.metadata.name).\(_subject)"]
  }
  if _subjects != _|_ {
    subject_names: [for s in _subjects {"spiffe://greymatter.io/\(mesh.metadata.name).\(s)"}]
  }
  ecdh_curves: ["X25519:P-256:P-521:P-384"]
}

#envoy_jwt_authn_filter: jwt_authn.#JwtAuthentication

#envoy_rbac_filter: rbac.#RBAC | *#default_rbac
#default_rbac: {
  rules: {
    action: "ALLOW",
    policies: {
      all: {
        permissions: [
          {
            any: true
          }
        ],
        principals: [
          { 
            any: true 
          }
        ]
      }
    }
  }
}