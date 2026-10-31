# Output helpers and checks shared by the build scripts; sourced, never run.
# shellcheck shell=bash
if [[ -t 1 ]]; then BOLD=$'\033[1m'; GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; NC=$'\033[0m'; else BOLD=""; GREEN=""; RED=""; NC=""; fi
step() { printf '\n%s%s%s\n' "$BOLD" "$*" "$NC"; }
ok()   { printf '%s✓%s %s\n' "$GREEN" "$NC" "$*"; }
fail() { printf '%s✗%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }
need_docker() {
  command -v docker >/dev/null 2>&1 || fail "docker is required to build the image"
  docker info >/dev/null 2>&1 || fail "docker daemon is not running (or you are not in the docker group)"
}
