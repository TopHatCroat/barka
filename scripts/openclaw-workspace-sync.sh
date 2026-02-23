#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Sync OpenClaw workspace to/from a local directory.

Required env:
  OPENCLAW_WORKSPACE_LOCAL_DIR   Local path to sync with

Optional env:
  OPENCLAW_NAMESPACE             Default: openclaw
  OPENCLAW_POD                   Default: auto-detect via label app.kubernetes.io/name=openclaw
  OPENCLAW_CONTAINER             Default: openclaw
  OPENCLAW_WORKSPACE_PATH        Default: /home/openclaw/.openclaw/workspace

Usage:
  openclaw-workspace-sync.sh pull   # pod -> local
  openclaw-workspace-sync.sh push   # local -> pod

Notes:
  - The workspace's .git, .cache, and .venv directories are excluded from sync.

Examples:
  # Using mise prod env (.env.prod) to provide kubeconfig + OPENCLAW_WORKSPACE_LOCAL_DIR
  mise -E prod exec -- scripts/openclaw-workspace-sync.sh pull

  # Direct
  OPENCLAW_WORKSPACE_LOCAL_DIR=~/openclaw-workspace scripts/openclaw-workspace-sync.sh pull
EOF
}

cmd="${1:-}"
case "$cmd" in
  pull|push) ;;
  -h|--help|help|"")
    usage
    exit 0
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac

: "${OPENCLAW_WORKSPACE_LOCAL_DIR:?Set OPENCLAW_WORKSPACE_LOCAL_DIR (e.g. /Users/you/openclaw-workspace)}"

ns="${OPENCLAW_NAMESPACE:-openclaw}"
container="${OPENCLAW_CONTAINER:-openclaw}"
workspace_path="${OPENCLAW_WORKSPACE_PATH:-/home/openclaw/.openclaw/workspace}"

pod="${OPENCLAW_POD:-}"
if [ -z "$pod" ]; then
  pod="$(kubectl -n "$ns" get pod -l app.kubernetes.io/name=openclaw -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi

if [ -z "$pod" ]; then
  echo "Failed to find OpenClaw pod in namespace '$ns' (label app.kubernetes.io/name=openclaw)." >&2
  echo "Set OPENCLAW_POD to override." >&2
  exit 1
fi

# Verify workspace path exists in container
if ! kubectl -n "$ns" exec "pod/$pod" -c "$container" -- sh -c "test -d '$workspace_path'" >/dev/null 2>&1; then
  echo "Workspace path not found in pod: $ns/$pod:$workspace_path" >&2
  echo "Override with OPENCLAW_WORKSPACE_PATH if needed." >&2
  exit 1
fi

local_dir="$OPENCLAW_WORKSPACE_LOCAL_DIR"

# macOS tar (bsdtar/libarchive) may include extended attributes (xattrs) in PAX
# headers. Some minimal tar implementations in containers (e.g., busybox) warn
# about unknown LIBARCHIVE.* headers when extracting. Force-disable mac metadata
# on the sending side.
tar_extra_flags=""
case "$(tar --version 2>/dev/null || true)" in
  bsdtar*)
    tar_extra_flags="--no-xattrs --no-acls --disable-copyfile --format=ustar"
    ;;
esac

case "$cmd" in
  pull)
    mkdir -p "$local_dir"
    echo "Pulling $ns/$pod:$workspace_path -> $local_dir" >&2
    kubectl -n "$ns" exec "pod/$pod" -c "$container" -- sh -c "tar -C '$workspace_path' -cf - --exclude='.git' --exclude='.cache' --exclude='.venv' ." | tar -C "$local_dir" -xf -
    ;;
  push)
    if [ ! -d "$local_dir" ]; then
      echo "Local dir does not exist: $local_dir" >&2
      exit 1
    fi
    echo "Pushing $local_dir -> $ns/$pod:$workspace_path" >&2
    COPYFILE_DISABLE=1 tar -C "$local_dir" -cf - $tar_extra_flags --exclude='.git' --exclude='.cache' --exclude='.venv' . | kubectl -n "$ns" exec -i "pod/$pod" -c "$container" -- sh -c "tar -C '$workspace_path' -xf -"
    ;;
esac
