#!/usr/bin/env bash
set -u

REPAIR_MANAGER=false
REFRESH=false
INSTALL_SECURITY=false
INSTALL_ALL=false
CLEAN_CACHE=false
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: linux_patch_repair.sh [options]

  --repair-manager      Repair interrupted package-manager state.
  --refresh             Refresh repository metadata.
  --install-security    Install security updates where supported.
  --install-all         Install all available updates.
  --clean-cache         Clean package-manager caches.
  --dry-run             Show commands without changing the system.
  --yes                 Skip confirmation prompts.
  --output DIR          Save logs and before/after verification in DIR.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repair-manager) REPAIR_MANAGER=true; shift ;;
    --refresh) REFRESH=true; shift ;;
    --install-security) INSTALL_SECURITY=true; shift ;;
    --install-all) INSTALL_ALL=true; shift ;;
    --clean-cache) CLEAN_CACHE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if ! $REPAIR_MANAGER && ! $REFRESH && ! $INSTALL_SECURITY && ! $INSTALL_ALL && ! $CLEAN_CACHE; then echo "Choose at least one repair action." >&2; exit 2; fi
if $INSTALL_SECURITY && $INSTALL_ALL; then echo "Choose security-only or all updates, not both." >&2; exit 2; fi

PM=""
command -v apt-get >/dev/null 2>&1 && PM=apt
[ -n "$PM" ] || { command -v dnf >/dev/null 2>&1 && PM=dnf; }
[ -n "$PM" ] || { command -v yum >/dev/null 2>&1 && PM=yum; }
[ -n "$PM" ] || { echo "Supported package manager not found." >&2; exit 3; }

STAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${OUTPUT_DIR:-./patch-repair-$STAMP}"
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/repair.log"
BEFORE="$OUTPUT_DIR/before.txt"
AFTER="$OUTPUT_DIR/after.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() { $ASSUME_YES && return 0; read -r -p "$1 [y/N]: " answer; case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac; }
run_action() {
  local description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then printf 'DRY-RUN:' >> "$LOG"; printf ' %q' "$@" >> "$LOG"; printf '\n' >> "$LOG"; return 0; fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
run_root() { local description="$1"; shift; if [ "$(id -u)" -eq 0 ]; then run_action "$description" "$@"; else run_action "$description" sudo "$@"; fi; }
collect_state() {
  local destination="$1"
  {
    echo "Collected: $(date -Is)"
    echo "Package manager: $PM"
    case "$PM" in
      apt) apt-get -s upgrade 2>&1 || true; [ -f /var/run/reboot-required ] && cat /var/run/reboot-required || true ;;
      dnf) dnf check-update 2>&1 || true; needs-restarting -r 2>&1 || true ;;
      yum) yum check-update 2>&1 || true; needs-restarting -r 2>&1 || true ;;
    esac
  } > "$destination"
}

collect_state "$BEFORE"
confirm "Apply the selected package and update actions using $PM?" || { log "Repair cancelled."; exit 10; }

case "$PM" in
  apt)
    $REPAIR_MANAGER && run_root "Completing interrupted dpkg configuration" dpkg --configure -a || true
    $REPAIR_MANAGER && run_root "Repairing broken APT dependencies" apt-get -f install -y || true
    $REFRESH && run_root "Refreshing APT metadata" apt-get update || true
    if $INSTALL_SECURITY; then
      if command -v unattended-upgrade >/dev/null 2>&1; then run_root "Installing configured security updates" unattended-upgrade -d; else FAILURES=$((FAILURES + 1)); log "WARNING: unattended-upgrade is not installed; security-only mode is unavailable."; fi
    fi
    $INSTALL_ALL && run_root "Installing all available APT updates" apt-get upgrade -y || true
    $CLEAN_CACHE && run_root "Cleaning APT cache" apt-get clean || true
    ;;
  dnf)
    $REPAIR_MANAGER && run_root "Checking DNF package state" dnf check || true
    $REFRESH && run_root "Refreshing DNF metadata" dnf makecache --refresh || true
    $INSTALL_SECURITY && run_root "Installing DNF security updates" dnf upgrade --security -y || true
    $INSTALL_ALL && run_root "Installing all DNF updates" dnf upgrade -y || true
    $CLEAN_CACHE && run_root "Cleaning DNF cache" dnf clean all || true
    ;;
  yum)
    $REPAIR_MANAGER && run_root "Checking YUM package state" yum check || true
    $REFRESH && run_root "Refreshing YUM metadata" yum makecache || true
    $INSTALL_SECURITY && run_root "Installing YUM security updates" yum update --security -y || true
    $INSTALL_ALL && run_root "Installing all YUM updates" yum update -y || true
    $CLEAN_CACHE && run_root "Cleaning YUM cache" yum clean all || true
    ;;
esac

collect_state "$AFTER"
if [ "$FAILURES" -gt 0 ]; then exit 20; fi
log "Repair completed successfully. Actions performed: $ACTIONS"
exit 0
