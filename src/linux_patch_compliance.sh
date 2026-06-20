#!/usr/bin/env bash
set -u

REFRESH=false
OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --refresh-metadata) REFRESH=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--refresh-metadata] [--output DIR]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./linux-patch-compliance-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/patch-compliance.txt"
CSV="$OUTPUT_DIR/pending-updates.csv"
JSON="$OUTPUT_DIR/patch-summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"; : > "$ERRORS"; echo 'package,current_version,candidate_version,security_related' > "$CSV"

section() { local title="$1"; shift; { printf '\n===== %s =====\n' "$title"; "$@"; } >> "$REPORT" 2>> "$ERRORS" || true; }
have() { command -v "$1" >/dev/null 2>&1; }

section "Collection metadata" bash -c 'date -Is; hostname -f 2>/dev/null || hostname; cat /etc/os-release 2>/dev/null || true'
MANAGER="unknown"
PENDING=0
SECURITY=0

if have apt-get; then
  MANAGER="apt"
  $REFRESH && { section "APT metadata refresh" apt-get update; }
  section "Configured APT repositories" bash -c 'grep -RhsE "^[[:space:]]*deb " /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true'
  section "Held packages" apt-mark showhold
  section "Pending updates" bash -c 'apt list --upgradable 2>/dev/null | sed 1d'
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    pkg="${line%%/*}"
    cand="$(awk '{print $2}' <<< "$line")"
    current="$(sed -n 's/.*upgradable from: \([^]]*\).*/\1/p' <<< "$line")"
    sec=false; grep -Eqi 'security|updates-security' <<< "$line" && sec=true
    printf '%s,%s,%s,%s\n' "$pkg" "${current:-unknown}" "${cand:-unknown}" "$sec" >> "$CSV"
  done < <(apt list --upgradable 2>/dev/null | sed 1d)
  PENDING="$(($(wc -l < "$CSV") - 1))"
  SECURITY="$(awk -F, 'NR>1 && $4=="true" {c++} END {print c+0}' "$CSV")"
elif have dnf; then
  MANAGER="dnf"
  $REFRESH && { section "DNF metadata refresh" dnf -q makecache; }
  section "Configured DNF repositories" dnf repolist --all
  section "Version locks" bash -c 'dnf versionlock list 2>/dev/null || true'
  section "Pending updates" bash -c 'dnf -q check-update 2>/dev/null || true'
  section "Security updates" bash -c 'dnf -q updateinfo list security 2>/dev/null || true'
  dnf -q check-update 2>/dev/null | awk 'NF>=3 && $1 !~ /^(Last|Obsoleting)/ {print $1",unknown,"$2",false"}' >> "$CSV" || true
  PENDING="$(($(wc -l < "$CSV") - 1))"
  SECURITY="$(dnf -q updateinfo list security 2>/dev/null | awk 'NF>2 {c++} END {print c+0}')"
elif have yum; then
  MANAGER="yum"
  $REFRESH && { section "YUM metadata refresh" yum -q makecache; }
  section "Configured YUM repositories" yum repolist all
  section "Pending updates" bash -c 'yum -q check-update 2>/dev/null || true'
  section "Security updates" bash -c 'yum -q updateinfo list security 2>/dev/null || true'
  yum -q check-update 2>/dev/null | awk 'NF>=3 {print $1",unknown,"$2",false"}' >> "$CSV" || true
  PENDING="$(($(wc -l < "$CSV") - 1))"
  SECURITY="$(yum -q updateinfo list security 2>/dev/null | awk 'NF>2 {c++} END {print c+0}')"
else
  echo "No supported package manager found." | tee -a "$REPORT"
fi

section "Automatic update services and timers" bash -c 'systemctl list-timers --all 2>/dev/null | grep -Ei "apt|dnf|yum|update" || true; systemctl status unattended-upgrades dnf-automatic.timer 2>/dev/null --no-pager || true'
REBOOT=false
[[ -f /var/run/reboot-required ]] && REBOOT=true
if command -v needs-restarting >/dev/null 2>&1; then needs-restarting -r >/dev/null 2>&1 || REBOOT=true; fi

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -Is)",
  "hostname": "$(hostname -f 2>/dev/null || hostname)",
  "package_manager": "$MANAGER",
  "pending_updates": ${PENDING:-0},
  "security_updates": ${SECURITY:-0},
  "reboot_required": $REBOOT,
  "metadata_refreshed": $REFRESH
}
EOF

printf '\nPatch compliance collection completed. Output: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
