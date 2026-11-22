#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template claude-test .)"
  export RENDERED
}

resource() {
  echo "$RENDERED" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

@test "namespace is claude" {
  ns=$(resource Namespace claude)
  [ -n "$ns" ]
}

@test "claude-backend Deployment references graph-claude's image by repository+tag and exposes port 8000" {
  image=$(resource Deployment claude-backend | yq '.spec.template.spec.containers[0].image')
  [ "$image" = "registry.morrisons.site/graph-claude:98d2d327b126f8f97d002b30a1abc81379dfe3f4" ]

  port=$(resource Deployment claude-backend | yq '.spec.template.spec.containers[0].ports[0].containerPort')
  [ "$port" = "8000" ]
}

@test "claude-backend Deployment sets CLAUDE_SERVICE_DB_PATH to /data/claude-service.db" {
  value=$(resource Deployment claude-backend | yq '.spec.template.spec.containers[0].env[] | select(.name == "CLAUDE_SERVICE_DB_PATH") | .value')
  [ "$value" = "/data/claude-service.db" ]
}

@test "claude-backend pulls via the claude-zot-pull-secret" {
  secret=$(resource Deployment claude-backend | yq '.spec.template.spec.imagePullSecrets[0].name')
  [ "$secret" = "claude-zot-pull-secret" ]
}

@test "claude-backend runs as the claude ServiceAccount" {
  sa=$(resource Deployment claude-backend | yq '.spec.template.spec.serviceAccountName')
  [ "$sa" = "claude" ]
}

@test "claude-backend mounts the claude-data PVC at /data and uses Recreate rollout strategy" {
  mount_path=$(resource Deployment claude-backend | yq '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "data") | .mountPath')
  [ "$mount_path" = "/data" ]

  claim=$(resource Deployment claude-backend | yq '.spec.template.spec.volumes[] | select(.name == "data") | .persistentVolumeClaim.claimName')
  [ "$claim" = "claude-data" ]

  strategy=$(resource Deployment claude-backend | yq '.spec.strategy.type')
  [ "$strategy" = "Recreate" ]
}
