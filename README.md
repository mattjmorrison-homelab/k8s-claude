# k8s-claude

## claude-prompt-runner

`claude-prompt-runner`'s `invoke_llm` function runs each prompt through the `claude` CLI (`claude -p "<prompt>" --allowedTools WebSearch`). The container has no credential mounted, so `claude -p` will fail with an auth error until a credential-mounting mechanism (e.g. a hostPath volume to an already-logged-in host, or some other auth delivery) is added separately.

The `@anthropic-ai/claude-code` npm package name used to install the `claude` CLI is unverified/assumed — confirm it before relying on this in production.
