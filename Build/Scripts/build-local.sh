#!/usr/bin/env bash
# Interactive macOS entry point. Uses the same ci-build.sh as GitHub Actions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

choose() {
  local label="$1" default="$2"; shift 2
  local options=("$@") answer
  if [[ -n "${!label:-}" ]]; then printf '%s' "${!label}"; return; fi
  echo "$label — choose one:" >&2
  local i=1
  for item in "${options[@]}"; do
    if [[ "$item" == "$default" ]]; then printf '  %d) %s [default]\n' "$i" "$item" >&2; else printf '  %d) %s\n' "$i" "$item" >&2; fi
    ((i+=1))
  done
  read -r -p "Selection (Enter for $default): " answer
  if [[ -z "$answer" ]]; then printf '%s' "$default"; elif [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#options[@]} )); then printf '%s' "${options[$((answer-1))]}"; else echo "Invalid selection: $answer" >&2; return 2; fi
}

ENVIRONMENT="$(choose ENVIRONMENT RootHide RootHide Rootless)"
PROFILE="$(choose PROFILE Auto Auto roothide-dopamine-ellekit-1.2-3-16e3e7e)"
CONFIGURATION="$(choose CONFIGURATION Release Debug Release)"
ARCHITECTURE="$(choose ARCHITECTURE arm64 arm64e arm64)"
RUN_TESTS="$(choose RUN_TESTS No Yes No)"
PACKAGE="$(choose PACKAGE None DEB IPA Both None)"
CLEAN_BUILD="$(choose CLEAN_BUILD Yes Yes No)"

export ENVIRONMENT PROFILE CONFIGURATION ARCHITECTURE
export RUN_TESTS="$( [[ "$RUN_TESTS" == Yes || "$RUN_TESTS" == true ]] && echo true || echo false )"
export CLEAN_BUILD="$( [[ "$CLEAN_BUILD" == Yes || "$CLEAN_BUILD" == true ]] && echo true || echo false )"
export PACKAGE

printf '\nFilterKit local build configuration\n'
printf 'Environment: %s\nProfile: %s\nConfiguration: %s\nArchitecture: %s\nTests: %s\nPackage: %s\nClean: %s\n\n' \
  "$ENVIRONMENT" "$PROFILE" "$CONFIGURATION" "$ARCHITECTURE" "$RUN_TESTS" "$PACKAGE" "$CLEAN_BUILD"
read -r -p 'Start build? [y/N] ' confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo 'Build cancelled.'; exit 0; }
exec bash "$ROOT/Build/Scripts/ci-build.sh"
