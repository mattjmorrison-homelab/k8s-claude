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

@test "claude-prompt-runner CronJob uses the pinned node image" {
  image=$(resource CronJob claude-prompt-runner | yq '.spec.jobTemplate.spec.template.spec.containers[0].image')
  [ "$image" = "node@sha256:2cf067cfed83d5ea958367df9f966191a942351a2df77d6f0193e162b5febfc0" ]
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

@test "run-prompts script's invoke_llm calls the claude CLI with WebSearch allowed" {
  grep -q 'claude -p "\$prompt"' scripts/run-prompts.sh
  grep -q -- '--allowedTools WebSearch' scripts/run-prompts.sh
}

@test "claude-prompt-runner CronJob has no hostPath volume" {
  hostpaths=$(resource CronJob claude-prompt-runner | yq '.spec.jobTemplate.spec.template.spec.volumes[] | select(.hostPath)')
  [ -z "$hostpaths" ]
}

@test "claude-prompt-runner CronJob has no nodeSelector" {
  selector=$(resource CronJob claude-prompt-runner | yq '.spec.jobTemplate.spec.template.spec.nodeSelector // "none"')
  [ "$selector" = "none" ]
}
