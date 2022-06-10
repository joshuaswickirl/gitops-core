// Grey Matter configuration for Edge

package greymatter

let Name= "edge"
let EgressToRedisName = "\(Name)_egress_to_redis"
let KeycloakEndpoint = "https://keycloak-demo.greymatter.services:8553"
let Domain = "20.84.197.187"
let ClientSecret = "3a4522e4-6ed0-4ba6-9135-13f0027c4b47"
let Realm = "greymatter"

edge_config: [
  #domain & { 
    domain_key: Name
    force_https: true
  },
  #listener & {
    listener_key: Name
    _gm_observables_topic: Name
    _is_ingress: true
    _enable_oidc_authentication: true
    _enable_jwt_authn: true 
    _enable_rbac: true

    http_filters: {
      "gm_oidc-authentication": {
        accessToken: {
          location: "cookie"
          key: "access_token"
          cookieOptions: {
            httpOnly: true
					  maxAge:   "6h"
					  domain:   Domain
					  path:     "/"
          }
        }
        idToken: {
          location: "cookie"
          key: "authz_token"
          cookieOptions: {
            httpOnly: true
					  maxAge:   "6h"
					  domain:   Domain
					  path:     "/"
          }
        }
        tokenRefresh: {
          enabled:   true
          endpoint:  KeycloakEndpoint
          realm:     Realm
          timeoutMs: 5000
          useTLS:    false
        }
        serviceUrl:   "http://\(Domain):10808"
        callbackPath: "/oauth"
        provider:     "\(KeycloakEndpoint)/auth/realms/\(Realm)"
        clientId:     "edge"
        clientSecret: ClientSecret
        additionalScopes: ["openid"]
      }
      "gm_ensure-variables": {
        rules: [
				{
					location: "cookie"
					key:      "access_token"
					copyTo: [
						{
							location: "header"
							key:      "access_token"
						},
					]
				}]
      }
      "envoy_jwt-authn": {

      }
    }
  },
  // This cluster must exist (though it never receives traffic)
  // so that Catalog will be able to look-up edge instances
  #cluster & { cluster_key: Name }, 

  // egress->redis
  #domain & { domain_key: EgressToRedisName, port: defaults.ports.redis_ingress },
  #cluster & {
    cluster_key: EgressToRedisName
    name: defaults.redis_cluster_name
    _spire_self: Name
    _spire_other: defaults.redis_cluster_name
  },
  #route & { route_key: EgressToRedisName }, // unused route must exist for the cluster to be registered with sidecar
  #listener & {
    listener_key: EgressToRedisName
    ip: "127.0.0.1" // egress listeners are local-only
    port: defaults.ports.redis_ingress
    _tcp_upstream: defaults.redis_cluster_name
  },

  #proxy & {
    proxy_key: Name
    domain_keys: [Name, EgressToRedisName]
    listener_keys: [Name, EgressToRedisName]
  },
]
