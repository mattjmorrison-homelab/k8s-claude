#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template claude-test .)"
  export RENDERED
}

resource() {
  echo "$RENDERED" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

@test "claude-backend Service targets port 8000" {
  port=$(resource Service claude-backend | yq '.spec.ports[0].port')
  target=$(resource Service claude-backend | yq '.spec.ports[0].targetPort')
  selector=$(resource Service claude-backend | yq '.spec.selector.app')
  [ "$port" = "8000" ]
  [ "$target" = "8000" ]
  [ "$selector" = "claude-backend" ]
}

@test "Ingress routes graph-claude.morrisons.site to claude-backend:8000" {
  service=$(resource Ingress claude | yq '.spec.rules[] | select(.host == "graph-claude.morrisons.site") | .http.paths[0].backend.service.name')
  port=$(resource Ingress claude | yq '.spec.rules[] | select(.host == "graph-claude.morrisons.site") | .http.paths[0].backend.service.port.number')
  [ "$service" = "claude-backend" ]
  [ "$port" = "8000" ]
}

@test "Ingress has exactly one host rule" {
  count=$(resource Ingress claude | yq '.spec.rules | length')
  [ "$count" = "1" ]
}
