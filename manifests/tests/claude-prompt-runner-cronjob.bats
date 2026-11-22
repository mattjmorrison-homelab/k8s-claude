#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  RENDERED="$(helm template claude-test .)"
  export RENDERED
}

resource() {
  echo "$RENDERED" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

@test "claude-prompt-runner CronJob runs every 5 minutes" {
  schedule=$(resource CronJob claude-prompt-runner | yq '.spec.schedule')
  [ "$schedule" = "*/5 * * * *" ]
}

@test "claude-prompt-runner CronJob forbids concurrent runs" {
  policy=$(resource CronJob claude-prompt-runner | yq '.spec.concurrencyPolicy')
  [ "$policy" = "Forbid" ]
}

@test "claude-prompt-runner CronJob uses the pinned alpine image" {
  image=$(resource CronJob claude-prompt-runner | yq '.spec.jobTemplate.spec.template.spec.containers[0].image')
  [ "$image" = "alpine@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc" ]
}

@test "claude-prompt-runner CronJob mounts its script ConfigMap read-only" {
  configmap=$(resource CronJob claude-prompt-runner | yq '.spec.jobTemplate.spec.template.spec.volumes[] | select(.name == "script") | .configMap.name')
  [ "$configmap" = "claude-prompt-runner-script" ]

  mount_path=$(resource CronJob claude-prompt-runner | yq '.spec.jobTemplate.spec.template.spec.containers[0].volumeMounts[] | select(.name == "script") | .mountPath')
  [ "$mount_path" = "/scripts" ]
}

@test "claude-prompt-runner-script ConfigMap is NOT an ArgoCD hook" {
  hook=$(resource ConfigMap claude-prompt-runner-script | yq '.metadata.annotations["argocd.argoproj.io/hook"] // "none"')
  [ "$hook" = "none" ]
}

@test "run-prompts script polls pendingPrompts and reports results back to graph-claude" {
  grep -q 'https://graph-claude.morrisons.site/' scripts/run-prompts.sh
  grep -q 'pendingPrompts' scripts/run-prompts.sh
  grep -q 'completePrompt' scripts/run-prompts.sh
  grep -q 'failPrompt' scripts/run-prompts.sh
}

@test "run-prompts script's invoke_llm is a stub that always fails" {
  grep -q 'invoke_llm not yet implemented' scripts/run-prompts.sh
}
