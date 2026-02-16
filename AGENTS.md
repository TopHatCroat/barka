# Agents Guide

This repo uses k3s (local) and plain kubectl (all envs), with task entrypoints managed by mise.

## Conventions

- Prefer mise tasks over ad-hoc commands.
- Use mise environments (`-E <name>`) to select a kubeconfig/cluster target.
- Keep tasks env-agnostic unless they inherently require local Docker/k3s lifecycle control.

## Task Naming

- `kube:*`: environment-agnostic kubectl operations. These run against whatever cluster is selected via mise environment (`KUBECONFIG`).
- `local:*`: local-only tasks (k3s-in-Docker lifecycle).
- `prod:*`: production wrappers around `kube:*` tasks. These should add guardrails like `confirm` prompts.

## Local Environment

- Compose: `dev/k3s/docker-compose.yml`
- Kubeconfig output (generated): `dev/k3s/kubeconfig/kubeconfig.yaml`
- Local mise env config: `mise.local.toml` (loads `.env.local`)
- Local env file (gitignored): `.env.local` (must include `KUBECONFIG=dev/k3s/kubeconfig/kubeconfig.yaml`)

## Production Environment

- Prod mise env config: `mise.production.toml`
- `KUBECONFIG` should be provided via your shell environment (not committed to the repo)

Infisical (production secrets):

- `kube:tools:apply` will install the Infisical Secrets Operator and create/update the Universal Auth credentials secret.
- You must export `INFISICAL_CLIENT_ID` and `INFISICAL_CLIENT_SECRET` in your shell before running production tasks.

Common commands:

```bash
mise trust
mise install

mise -E local run local:up
mise -E local run kube:kubectl -- get pods -A
mise -E local run kube:headlamp:token

mise -E local run local:down
mise -E local run local:reset
```

## Tools Manifests

- Tools are installed by `kube:tools:apply`.
- Headlamp is managed by an in-repo Helm chart at `charts/headlamp/`.
- Avoid generating or storing credentials in the repo. Tokens are created on-demand via `kube:headlamp:token`.

## Safety

- Use `local:reset` when you need a clean slate (wipes the Docker volume and removes the generated kubeconfig file).
- For production, prefer `prod:*` tasks for any mutating action.
- Do not run any production related commands yourself, instead show them in the output
- Do not commit anything instead of me
  
