#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template claude-test .)"
  export RENDERED
}

resource() {
  echo "$RENDERED" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

@test "claude-verify Job is a PostSync hook with BeforeHookCreation,HookSucceeded delete policy" {
  hook=$(resource Job claude-verify | yq '.metadata.annotations["argocd.argoproj.io/hook"]')
  policy=$(resource Job claude-verify | yq '.metadata.annotations["argocd.argoproj.io/hook-delete-policy"]')
  [ "$hook" = "PostSync" ]
  [ "$policy" = "BeforeHookCreation,HookSucceeded" ]
}

@test "claude-verify Job's expected commit SHA comes from the backend image tag" {
  backend_sha=$(resource Job claude-verify | yq '.spec.template.spec.containers[0].env[] | select(.name == "EXPECTED_BACKEND_COMMIT_SHA") | .value')
  [ "$backend_sha" = "98d2d327b126f8f97d002b30a1abc81379dfe3f4" ]
}

@test "verify script checks /version on the graph-claude hostname" {
  grep -q 'https://graph-claude.morrisons.site/version' scripts/verify.sh
}

@test "claude-verify-script ConfigMap is also a PostSync hook" {
  hook=$(resource ConfigMap claude-verify-script | yq '.metadata.annotations["argocd.argoproj.io/hook"]')
  [ "$hook" = "PostSync" ]
}
