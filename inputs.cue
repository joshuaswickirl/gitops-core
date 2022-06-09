package greymatter

import (
  corev1 "k8s.io/api/core/v1"
  "github.com/greymatter-io/common/api/meshv1"
)

config: {
  // Flags
  spire: bool | *false @tag(spire,type=bool) // enable Spire-based mTLS
  auto_apply_mesh: bool | *true @tag(auto_apply_mesh,type=bool) // apply the default mesh specified above after a delay
  openshift: bool | *false @tag(openshift,type=bool)

  debug: bool | *false @tag(debug,type=bool) // currently just controls k8s/outputs/operator.cue for debugging
  test: bool | *false @tag(test,type=bool) // currently just TURNS OFF GITOPS so CI integration tests can manipulate directly


  // for a hypothetical future where we want to mount specific certificates for operator webhooks, etc.
  generate_webhook_certs: bool | *true @tag(generate_webhook_certs,type=bool)
  cluster_ingress_name: string | *"cluster" // For OpenShift deployments, this is used to look up the configured ingress domain
}

mesh: meshv1.#Mesh & {
  metadata: {
    name: string | *"greymatter-mesh"
  }
  spec: {
    install_namespace: string | *"greymatter"
    watch_namespaces: [...string] | *["default"]
    release_version: string | *"1.7" // no longer does anything, for the moment
    zone: string | *"default-zone"
    images: { // TODO start with defaults from below
      proxy: string | *"docker.greymatter.io/release/gm-proxy:1.7.0-rc.4"
      catalog: string | *"docker.greymatter.io/release/gm-catalog:3.0.0"
      dashboard: string | *"docker.greymatter.io/release/gm-dashboard:6.0.0"

      control: string | *"docker.greymatter.io/internal/gm-control:1.7.1"
      control_api: string | *"docker.greymatter.io/internal/gm-control-api:1.7.1"

      redis: string | *"redis:latest"

    }
  }
}

defaults: {
  image_pull_secret_name: string | *"gm-docker-secret"
  image_pull_policy: corev1.#enumPullPolicy | *corev1.#PullAlways
  xds_host: "controlensemble.\(mesh.spec.install_namespace).svc.cluster.local"
  redis_cluster_name: "redis"
  redis_host: "\(redis_cluster_name).\(mesh.spec.install_namespace).svc.cluster.local"
  sidecar_list: [...string] | *["dashboard", "catalog", "controlensemble", "edge"]

  ports: {
    default_ingress: 10808
    redis_ingress: 10910
  }

  images: {
    operator: string | *"docker.greymatter.io/internal/gm-operator:latest" @tag(operator_image) // cibuild uses the tag
  }

}