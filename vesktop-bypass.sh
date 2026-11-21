#!/usr/bin/env bash
#
# vesktop-bypass.sh - Run Vesktop inside an isolated network namespace whose
# only route to the internet is a WireGuard tunnel. The rest of the system's
# network is never modified.
#
# How it works:
#   1. Create a network namespace (empty: only a loopback interface).
#   2. Create a WireGuard interface in the host namespace (so its UDP socket
#      can reach the VPN endpoint), then move it into the new namespace.
#   3. Configure address, default route, and DNS inside the namespace only.
#   4. Start Vesktop inside the namespace as your normal, unprivileged user.
#   5. When Vesktop exits (or on Ctrl-C), remove everything that was created.
#
# Kill switch: the namespace has no other interface. If the tunnel breaks,
# Vesktop loses connectivity instead of falling back to your real network.
#
# Usage: see `vesktop-bypass.sh --help`.

set -Eeuo pipefail
umask 077

readonly PROG="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly NS_PREFIX="vesktop-"
readonly DEFAULT_MTU=1420
readonly FALLBACK_DNS="1.1.1.1"

# Resources owned by this run (used by cleanup).
NS_NAME="${NS_PREFIX}$$"
WG_IF="wgvb$$"
WORK_DIR=""
NS_CREATED=0
WG_CREATED=0
RESOLV_DIR=""

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

log()  { printf '[%s] %s\n' "$PROG" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$PROG" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$PROG" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $PROG [options] [WG_CONF] [-- VESKTOP_ARGS...]

Run Vesktop isolated in a network namespace, routed only through WireGuard.

Arguments:
  WG_CONF         Path to a WireGuard .conf file. If omitted, the first of
                  these that exists is used:
                    1. \$VESKTOP_WG_CONF
                    2. \$XDG_CONFIG_HOME/vesktop-netns/wg.conf
                       (default: ~/.config/vesktop-netns/wg.conf)
                    3. ./wg.conf next to this script

Options:
  -t, --test      Do not start Vesktop. Print the public IP seen through the
                  tunnel, then clean up. Use it to check your .conf file.
  -c, --cleanup   Remove leftover namespaces from crashed runs, then exit.
  -h, --help      Show this help.

Environment:
  VESKTOP_WG_CONF   Default WireGuard config path.
  VESKTOP_CMD       Command used to start Vesktop (default: auto-detect
                    "vesktop", then the Flatpak "dev.vencord.Vesktop").
  VESKTOP_DNS       Comma-separated DNS servers; overrides the config's DNS.

Anything after "--" is passed to Vesktop unchanged.
EOF
}

# ---------------------------------------------------------------------------
# Privileged command helpers
# ---------------------------------------------------------------------------

# Run a command as root. Only network setup uses root; Vesktop never does.
priv() { sudo -- "$@"; }

require_commands() {
  local missing=() cmd
  for cmd in ip wg wg-quick sudo setpriv; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if ((${#missing[@]})); then
    die "Missing required commands: ${missing[*]}. Run 'make deps' in the repository, or see the README."
  fi
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

# Idempotent; runs on every exit path (normal exit, error, Ctrl-C, SIGTERM).
cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP ERR
  set +e

  if ((NS_CREATED)); then
    # Stop anything still running in the namespace so it can be removed.
    local pids
    pids="$(priv ip netns pids "$NS_NAME" 2>/dev/null)"
    # shellcheck disable=SC2086
    [[ -n "$pids" ]] && priv kill $pids 2>/dev/null
    priv ip netns del "$NS_NAME" 2>/dev/null
  fi
  # If the interface was never moved into the namespace, remove it from the host.
  ((WG_CREATED)) && priv ip link del "$WG_IF" 2>/dev/null
  [[ -n "$RESOLV_DIR" ]] && priv rm -rf -- "$RESOLV_DIR" 2>/dev/null
  [[ -n "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"

  ((NS_CREATED)) && log "Cleaned up namespace $NS_NAME."
  exit "$rc"
}

# Remove namespaces left behind by runs that were killed with SIGKILL.
cleanup_leftovers() {
  local ns found=0
  while read -r ns _; do
    [[ "$ns" == "$NS_PREFIX"* ]] || continue
    found=1
    log "Removing leftover namespace $ns"
    local pids
    pids="$(priv ip netns pids "$ns" 2>/dev/null || true)"
    # shellcheck disable=SC2086
    [[ -n "$pids" ]] && priv kill $pids 2>/dev/null || true
    priv ip netns del "$ns" || true
    priv rm -rf -- "/etc/netns/$ns" || true
  done < <(ip netns list 2>/dev/null)
  ((found)) || log "No leftover namespaces found."
}

# ---------------------------------------------------------------------------
# Config handling
# ---------------------------------------------------------------------------

resolve_conf_path() {
  local arg="${1:-}" candidate
  if [[ -n "$arg" ]]; then
    printf '%s\n' "$arg"
    return
  fi
  for candidate in \
    "${VESKTOP_WG_CONF:-}" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/vesktop-netns/wg.conf" \
    "$SCRIPT_DIR/wg.conf"; do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  die "No WireGuard config found. Pass a path, or save one as ~/.config/vesktop-netns/wg.conf (see README)."
}

# Print the value(s) of a key from the [Interface] section, one per line,
# splitting comma-separated lists. Keys are case-insensitive.
conf_interface_values() {
  local file="$1" key="$2"
  awk -v key="$(tr '[:upper:]' '[:lower:]' <<<"$key")" '
    { sub(/[#;].*$/, "") }                      # strip comments
    /^[[:space:]]*\[/ { in_if = (tolower($0) ~ /^[[:space:]]*\[interface\]/); next }
    in_if && index($0, "=") {
      k = substr($0, 1, index($0, "=") - 1)
      v = substr($0, index($0, "=") + 1)
      gsub(/[[:space:]]/, "", k)
      if (tolower(k) == key) {
        n = split(v, parts, ",")
        for (i = 1; i <= n; i++) { gsub(/[[:space:]]/, "", parts[i]); if (parts[i] != "") print parts[i] }
      }
    }' "$file"
}

validate_conf() {
  local file="$1" mode
  [[ -f "$file" && -r "$file" ]] || die "Cannot read WireGuard config: $file"
  mode="$(stat -c '%a' "$file")"
  if [[ "${mode: -2}" != "00" ]]; then
    warn "$file is readable by other users (mode $mode). It contains a private key; run: chmod 600 '$file'"
  fi
  grep -qiE '^[[:space:]]*PrivateKey[[:space:]]*=' "$file" \
    || die "$file has no PrivateKey. Is it a valid WireGuard config?"
  grep -qiE '^[[:space:]]*\[Peer\]' "$file" \
    || die "$file has no [Peer] section."
}

# ---------------------------------------------------------------------------
# Namespace setup
# ---------------------------------------------------------------------------

setup_namespace() {
  local conf="$1"
  local -a addresses=() dns=()
  local mtu addr has_v6=0

  mapfile -t addresses < <(conf_interface_values "$conf" Address)
  ((${#addresses[@]})) || die "$conf has no Address in [Interface]."

  if [[ -n "${VESKTOP_DNS:-}" ]]; then
    IFS=',' read -r -a dns <<<"${VESKTOP_DNS// /}"
  else
    mapfile -t dns < <(conf_interface_values "$conf" DNS)
  fi
  if ((${#dns[@]} == 0)); then
    warn "No DNS in config. Using $FALLBACK_DNS (queried through the tunnel)."
    dns=("$FALLBACK_DNS")
  fi

  mtu="$(conf_interface_values "$conf" MTU | head -n1)"
  mtu="${mtu:-$DEFAULT_MTU}"
  [[ "$mtu" =~ ^[0-9]+$ ]] || die "Invalid MTU in config: $mtu"

  # Validate values before they reach privileged commands.
  for addr in "${addresses[@]}"; do
    [[ "$addr" =~ ^[0-9a-fA-F:.]+(/[0-9]+)?$ ]] || die "Invalid Address in config: $addr"
    [[ "$addr" == *:* ]] && has_v6=1
  done
  for addr in "${dns[@]}"; do
    [[ "$addr" =~ ^[0-9a-fA-F:.]+$ ]] || die "Invalid DNS server: $addr (use IP addresses only)"
  done

  # "wg-quick strip" removes wg-quick-only keys (Address, DNS, PostUp, ...) so
  # "wg setconf" accepts the file. It never executes PostUp/PreUp hooks. It
  # derives the interface name from the file name, so use a private symlink.
  WORK_DIR="$(mktemp -d)"
  ln -s "$(realpath -- "$conf")" "$WORK_DIR/wgvb.conf"

  # Load the kernel module if needed and fail early with a clear message.
  priv modprobe wireguard 2>/dev/null || true
  if ! priv ip link add "wgchk$$" type wireguard 2>/dev/null; then
    die "The kernel cannot create WireGuard interfaces. If you updated the kernel, reboot. Otherwise install a WireGuard-capable kernel (5.6+)."
  fi
  priv ip link del "wgchk$$" 2>/dev/null || true

  log "Creating namespace $NS_NAME"
  priv ip netns add "$NS_NAME"
  NS_CREATED=1
  priv ip -n "$NS_NAME" link set lo up

  log "Creating WireGuard interface $WG_IF"
  priv ip link add "$WG_IF" type wireguard
  WG_CREATED=1
  # The private key travels through a pipe, never through a file on disk.
  wg-quick strip "$WORK_DIR/wgvb.conf" | priv wg setconf "$WG_IF" /dev/stdin

  # Moving the interface keeps its UDP socket in the host namespace, so the
  # encrypted packets can reach the VPN server while apps inside cannot
  # reach anything else.
  priv ip link set "$WG_IF" netns "$NS_NAME"
  WG_CREATED=0

  for addr in "${addresses[@]}"; do
    priv ip -n "$NS_NAME" addr add "$addr" dev "$WG_IF"
  done
  priv ip -n "$NS_NAME" link set "$WG_IF" mtu "$mtu" up
  priv ip -n "$NS_NAME" route add default dev "$WG_IF"
  # Without an IPv6 address there is no IPv6 route, so IPv6 cannot leak.
  ((has_v6)) && priv ip -n "$NS_NAME" -6 route add default dev "$WG_IF"

  # "ip netns exec" bind-mounts /etc/netns/<name>/resolv.conf over
  # /etc/resolv.conf for processes inside the namespace only.
  RESOLV_DIR="/etc/netns/$NS_NAME"
  priv mkdir -p -- "$RESOLV_DIR"
  printf 'nameserver %s\n' "${dns[@]}" | priv tee "$RESOLV_DIR/resolv.conf" >/dev/null

  wait_for_handshake "${dns[0]}"
  log "Tunnel ready (DNS: ${dns[*]})."
}

# WireGuard only handshakes when traffic is sent. Send one UDP packet to the
# DNS server, then wait up to 10 seconds for the handshake to complete.
wait_for_handshake() {
  local probe_target="$1" i hs
  priv ip netns exec "$NS_NAME" bash -c "echo > /dev/udp/${probe_target}/53" 2>/dev/null || true
  for ((i = 0; i < 20; i++)); do
    hs="$(priv ip netns exec "$NS_NAME" wg show "$WG_IF" latest-handshakes | awk '{print $2}' | head -n1)"
    [[ -n "$hs" && "$hs" != "0" ]] && return 0
    sleep 0.5
  done
  die "No WireGuard handshake with the server after 10 seconds. Check that the config is valid and not expired, that your network allows outgoing UDP, or try another server."
}

# ---------------------------------------------------------------------------
# Running programs inside the namespace as the unprivileged user
# ---------------------------------------------------------------------------

# Environment variables forwarded so the app finds your display and audio.
readonly -a FORWARD_VARS=(
  HOME USER LOGNAME LANG LANGUAGE PATH SHELL
  XDG_RUNTIME_DIR XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_DATA_DIRS
  XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME
  WAYLAND_DISPLAY DISPLAY XAUTHORITY
  DBUS_SESSION_BUS_ADDRESS
  PULSE_SERVER PULSE_COOKIE PIPEWIRE_REMOTE
  GTK_THEME QT_QPA_PLATFORM
)

# Run "$@" inside the namespace with root privileges dropped to the invoking
# user, with display/audio environment preserved.
run_in_namespace() {
  local -a env_args=()
  local var
  for var in "${FORWARD_VARS[@]}"; do
    [[ -n "${!var:-}" ]] && env_args+=("$var=${!var}")
  done
  # Default so PipeWire/PulseAudio sockets in the runtime dir are found.
  [[ -n "${XDG_RUNTIME_DIR:-}" ]] || env_args+=("XDG_RUNTIME_DIR=/run/user/$(id -u)")

  priv ip netns exec "$NS_NAME" \
    setpriv --reuid="$(id -u)" --regid="$(id -g)" --init-groups \
    env -i "${env_args[@]}" "$@"
}

# Electron records the owning process in a "SingletonLock" symlink
# ("<host>-<pid>") inside the app's config directory.
vesktop_already_running() {
  local lock target pid
  for lock in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/vesktop/SingletonLock" \
    "$HOME/.var/app/dev.vencord.Vesktop/config/vesktop/SingletonLock"; do
    [[ -L "$lock" ]] || continue
    target="$(readlink -- "$lock")"
    pid="${target##*-}"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && return 0
  done
  return 1
}

detect_vesktop_cmd() {
  if [[ -n "${VESKTOP_CMD:-}" ]]; then
    printf '%s\n' "$VESKTOP_CMD"
  elif command -v vesktop >/dev/null 2>&1; then
    printf 'vesktop\n'
  elif command -v flatpak >/dev/null 2>&1 && flatpak info dev.vencord.Vesktop >/dev/null 2>&1; then
    printf 'flatpak run dev.vencord.Vesktop\n'
  else
    die "Vesktop not found. Install it, or set VESKTOP_CMD (see README)."
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  local conf_arg="" test_only=0
  local -a vesktop_args=()

  while (($#)); do
    case "$1" in
      -h|--help)    usage; exit 0 ;;
      -t|--test)    test_only=1 ;;
      -c|--cleanup) require_commands; sudo -v; cleanup_leftovers; exit 0 ;;
      --)           shift; vesktop_args=("$@"); break ;;
      -*)           die "Unknown option: $1 (try --help)" ;;
      *)            [[ -z "$conf_arg" ]] || die "Only one config file is accepted."
                    conf_arg="$1" ;;
    esac
    shift
  done

  ((EUID != 0)) || die "Run as your normal user, not root. The script uses sudo only for network setup."
  [[ "$(uname -s)" == "Linux" ]] || die "Linux only."
  require_commands

  local conf
  conf="$(resolve_conf_path "$conf_arg")"
  validate_conf "$conf"

  local -a cmd=()
  if ((test_only)); then
    command -v curl >/dev/null 2>&1 || die "--test needs curl."
    cmd=(curl -fsS --max-time 15 https://ifconfig.me)
  else
    # A running Vesktop would receive the launch request and exit, leaving the
    # new window outside the namespace. Refuse instead of leaking.
    if vesktop_already_running; then
      die "Vesktop is already running outside the tunnel. Close it completely (including the tray icon) and retry."
    fi
    read -r -a cmd <<<"$(detect_vesktop_cmd)"
    cmd+=("${vesktop_args[@]}")
  fi

  log "Requesting administrator access for network setup..."
  sudo -v

  trap cleanup EXIT INT TERM HUP ERR
  setup_namespace "$conf"

  if ((test_only)); then
    log "Public IP seen through the tunnel:"
    run_in_namespace "${cmd[@]}"
    echo
  else
    log "Starting: ${cmd[*]}"
    run_in_namespace "${cmd[@]}" || warn "Vesktop exited with a non-zero status."
  fi
}

main "$@"
