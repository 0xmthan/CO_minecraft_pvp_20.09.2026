#!/usr/bin/env bash
#
# PrismLauncher setup for the CO Minecraft PvP event.
#
# Installs the patched Prism build, creates an offline account named after
# your Unix login, creates the event's Fabric instance, and -- if you pass the
# server's address -- puts it in the in-game server list. Then it starts the
# launcher detached, so the terminal can be closed, and gets out of the way:
# picking the instance and hitting Play is yours.
#
# Everything -- app, user data, downloads -- stays under INSTALL_ROOT.
# Nothing is written to $HOME.
#
# Usage:
#   ./prism.sh                        # set up and open the launcher
#   ./prism.sh 10.11.12.13            # ... and add that server to the list
#   ./prism.sh 10.11.12.13:25566      # non-default port
#
# Script-only flags (consumed here, not passed to PrismLauncher):
#   --reinstall     re-download the app, keeping user data
#   --resetup       rebuild account / instance / server entry
#   --no-launch     set up only, do not open the launcher
#   --uninstall     remove the app (user data kept unless --purge)
#   --purge         with --uninstall, also delete user data
#
# Anything else starting with "-" is forwarded to PrismLauncher.
#
# Env override:
#   INSTALL_ROOT        install location

set -euo pipefail

# --- configuration --------------------------------------------------------
SERVER_NAME="CO PvP"
INSTANCE_NAME="CO PvP"

MC_VERSION="26.2"
FABRIC_VERSION="0.19.5"
INSTALL_ROOT="${INSTALL_ROOT:-/sgoinfre/$USER/[CO]minecraft_pvp_20.09.2026}"

PRISM_REPO="0xmthan/CO_minecraft_pvp_20.09.2026"
APPIMAGE_NAME="PrismLauncher-Linux-x86_64.AppImage"
APPIMAGE_URL="https://github.com/${PRISM_REPO}/releases/latest/download/${APPIMAGE_NAME}"
SCRIPT_URL="https://raw.githubusercontent.com/${PRISM_REPO}/main/prism.sh"

PRISM_DIR="${INSTALL_ROOT}/PrismLauncher"          # the AppImage lives here
DATA_DIR="${INSTALL_ROOT}/data"                    # accounts, instances, mods
BIN="${PRISM_DIR}/${APPIMAGE_NAME}"

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    C_OFF=$'\033[0m'; C_DIM=$'\033[2m';    C_BOLD=$'\033[1m'
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_ACT=$'\033[36m'
else
    C_OFF= C_DIM= C_BOLD= C_OK= C_WARN= C_ERR= C_ACT=
fi

# ok <label> <value>   -- a finished step, in an aligned two-column list
ok()   { printf '  %s✓%s %s%-9s%s %s\n' "${C_OK}" "${C_OFF}" "${C_DIM}" "$1" "${C_OFF}" "$2" >&2; }
step() { printf '  %s▸%s %s\n' "${C_ACT}" "${C_OFF}" "$*" >&2; }
note() { printf '    %s%s%s\n' "${C_DIM}" "$*" "${C_OFF}" >&2; }
warn() { printf '  %s!%s %s\n' "${C_WARN}" "${C_OFF}" "$*" >&2; }
die()  { printf '  %s✗%s %s\n' "${C_ERR}" "${C_OFF}" "$*" >&2; exit 1; }
log()  { step "$@"; }

# --- argument split -------------------------------------------------------
REINSTALL=0 RESETUP=0 LAUNCH=1 UNINSTALL=0 PURGE=0
ADDRESS=""
PRISM_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --reinstall)  REINSTALL=1 ;;
        --resetup)    RESETUP=1 ;;
        --no-launch)  LAUNCH=0 ;;
        --uninstall)  UNINSTALL=1 ;;
        --purge)      PURGE=1 ;;
        -*)           PRISM_ARGS+=("$arg") ;;
        *)            ADDRESS="$arg" ;;
    esac
done

if [ "${UNINSTALL}" -eq 1 ]; then
    log "Removing ${PRISM_DIR}"
    rm -rf -- "${PRISM_DIR}"
    if [ "${PURGE}" -eq 1 ]; then
        log "Purging user data"
        rm -rf -- "${DATA_DIR}"
    else
        log "Kept user data in ${DATA_DIR} (--purge to delete it too)"
    fi
    exit 0
fi

SERVER=""
if [ -n "${ADDRESS}" ]; then
    case "${ADDRESS}" in
        *:*) SERVER="${ADDRESS}" ;;
        *)   SERVER="${ADDRESS}:25565" ;;
    esac
fi

printf '\n  %sCO Minecraft PvP%s %s— Prism setup%s\n\n' \
    "${C_BOLD}" "${C_OFF}" "${C_DIM}" "${C_OFF}" >&2

# --- install --------------------------------------------------------------
if command -v curl >/dev/null; then
    HAVE_CURL=1
elif command -v wget >/dev/null; then
    HAVE_CURL=0
else
    die "need curl or wget"
fi

fetch() {
    if [ "${HAVE_CURL}" -eq 1 ]; then
        curl -fL --retry 3 --retry-delay 2 --progress-bar -o "$2" "$1"
    else
        wget -q --show-progress -O "$2" "$1"
    fi
}

is_appimage() {
    [ -s "$1" ] || return 1
    [ "$(stat -c %s -- "$1" 2>/dev/null || echo 0)" -gt 1000000 ] || return 1
    [ "$(od -An -tx1 -N4 -- "$1" 2>/dev/null | tr -d ' \n')" = "7f454c46" ]
}

install_prism() {
    mkdir -p -- "${PRISM_DIR}" \
        || die "cannot create ${INSTALL_ROOT} -- is /sgoinfre mounted?"
    [ -w "${INSTALL_ROOT}" ] || die "${INSTALL_ROOT} is not writable"

    [ "${REINSTALL}" -eq 1 ] && rm -f -- "${BIN}"

    step "Downloading the launcher, about 100MB"
    rm -f -- "${BIN}.part"
    fetch "${APPIMAGE_URL}" "${BIN}.part" \
        || { rm -f -- "${BIN}.part"; die "download failed: ${APPIMAGE_URL}"; }
    is_appimage "${BIN}.part" || {
        rm -f -- "${BIN}.part"
        die "downloaded file is not an AppImage -- rerun the script"
    }
    mv -- "${BIN}.part" "${BIN}"
    chmod +x "${BIN}"
}

if is_appimage "${BIN}" && [ "${REINSTALL}" -eq 0 ]; then
    ok "Launcher" "already installed"
else
    install_prism
    ok "Launcher" "PrismLauncher (patched)"
fi

mkdir -p -- "${DATA_DIR}"

# --- player name ----------------------------------------------------------
PLAYER="${USER:-$(id -un 2>/dev/null || true)}"
PLAYER="$(printf '%s' "${PLAYER}" | tr -c 'A-Za-z0-9_' '_' | cut -c1-16)"
[ -n "${PLAYER}" ] || PLAYER="Player"

# --- launcher settings ----------------------------------------------------
cfg_put() {
    python3 - "${DATA_DIR}/prismlauncher.cfg" "$@" <<'PY'
import os, sys

path, mode, pairs = sys.argv[1], sys.argv[2], sys.argv[3:]
wanted = dict(p.split("=", 1) for p in pairs)

lines = []
if os.path.exists(path):
    with open(path) as f:
        lines = f.read().splitlines()

if "[General]" not in lines:
    lines.insert(0, "[General]")

seen = set()
for i, ln in enumerate(lines):
    k = ln.split("=", 1)[0].strip()
    if k in wanted:
        seen.add(k)
        if mode == "force":
            lines[i] = f"{k}={wanted[k]}"

add = [f"{k}={v}" for k, v in wanted.items() if k not in seen]
if add:
    i = lines.index("[General]") + 1
    lines[i:i] = add

tmp = path + ".tmp"
with open(tmp, "w") as f:
    f.write("\n".join(lines) + "\n")
os.replace(tmp, path)
PY
}

cfg_put keep \
    "ConfigVersion=1.3" \
    "Language=en_US" \
    "ApplicationTheme=system" \
    "IconTheme=pe_colored" \
    "AutomaticJavaDownload=true" \
    "AutomaticJavaSwitch=true" \
    "UserAskedAboutAutomaticJavaDownload=true" \
    "IgnoreJavaWizard=true" \
    "PastebinURL=" \
    "LastHostname=$(hostname 2>/dev/null || echo localhost)"

# --- offline account ------------------------------------------------------
ACCOUNTS="${DATA_DIR}/accounts.json"
setup_account() {
    python3 - "${ACCOUNTS}" "${PLAYER}" <<'PY'
import hashlib, json, os, sys, time

path, player = sys.argv[1], sys.argv[2]

# Servers in offline mode derive a player's UUID as an MD5 (version 3) hash of
# "OfflinePlayer:<name>". Matching that keeps the same identity/inventory
# across rejoins and between clients.
h = bytearray(hashlib.md5(f"OfflinePlayer:{player}".encode()).digest())
h[6] = (h[6] & 0x0F) | 0x30          # version 3
h[8] = (h[8] & 0x3F) | 0x80          # RFC 4122 variant
uuid = h.hex()

account = {
    "active": True,
    "profile": {"capes": [], "id": uuid, "name": player,
                "skin": {"id": "", "url": "", "variant": ""}},
    "type": "Offline",
    "ygg": {"exp": int(time.time()) + 86400 * 3650, "extra": {"userName": player},
            "iss": "offline", "token": "0"},
}

data = {"accounts": [], "formatVersion": 3}
if os.path.exists(path):
    try:
        data = json.load(open(path))
        data.setdefault("accounts", [])
        data.setdefault("formatVersion", 3)
    except (json.JSONDecodeError, OSError):
        pass                          # unreadable -> start clean

# Don't duplicate, and never disturb a real Microsoft account that is present.
for a in data["accounts"]:
    if a.get("type") == "Offline" and a.get("profile", {}).get("name") == player:
        sys.exit(0)
if not any(a.get("active") for a in data["accounts"]):
    account["active"] = True
else:
    account["active"] = False
data["accounts"].append(account)

tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=4)
os.replace(tmp, path)
PY
}

account_exists() {
    [ -f "${ACCOUNTS}" ] && python3 - "${ACCOUNTS}" "${PLAYER}" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if any(a.get("type") == "Offline"
                  and a.get("profile", {}).get("name") == sys.argv[2]
                  for a in d.get("accounts", [])) else 1)
PY
}

account_exists || setup_account
ok "Account" "${PLAYER}"

# --- instance -------------------------------------------------------------
INSTANCE_DIR="${DATA_DIR}/instances/${INSTANCE_NAME}"
MC_DIR="${INSTANCE_DIR}/minecraft"

write_pack() {
    cat > "${INSTANCE_DIR}/mmc-pack.json" <<EOF
{
    "components": [
        {
            "important": true,
            "uid": "net.minecraft",
            "version": "${MC_VERSION}"
        },
        {
            "uid": "net.fabricmc.fabric-loader",
            "version": "${FABRIC_VERSION}"
        }
    ],
    "formatVersion": 1
}
EOF
}

setup_instance() {
    mkdir -p -- "${MC_DIR}"
    write_pack

    cat > "${INSTANCE_DIR}/instance.cfg" <<EOF
[General]
ConfigVersion=1.3
InstanceType=OneSix
name=${INSTANCE_NAME}
iconKey=default
notes=Created by prism.sh for the CO Minecraft PvP event.
EOF
}

pack_is_current() {
    python3 - "${INSTANCE_DIR}/mmc-pack.json" "${MC_VERSION}" "${FABRIC_VERSION}" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
want = {"net.minecraft": sys.argv[2], "net.fabricmc.fabric-loader": sys.argv[3]}
have = {c.get("uid"): c.get("version") for c in d.get("components", [])}
sys.exit(0 if all(have.get(u) == v for u, v in want.items()) else 1)
PY
}

if [ ! -f "${INSTANCE_DIR}/instance.cfg" ] || [ "${RESETUP}" -eq 1 ]; then
    setup_instance
elif ! pack_is_current; then
    write_pack                        # an older run pinned something else
fi
ok "Instance" "${INSTANCE_NAME} ${C_DIM}— Minecraft ${MC_VERSION}, Fabric ${FABRIC_VERSION}${C_OFF}"

# --- in-game defaults -----------------------------------------------------
OPTIONS_DEFAULTS="guiScale:3 fov:1.0"

apply_options() {
    local marker="${INSTANCE_DIR}/.event-options"
    [ "$(cat "${marker}" 2>/dev/null || true)" = "${OPTIONS_DEFAULTS}" ] && return 1

    mkdir -p -- "${MC_DIR}"
    python3 - "${MC_DIR}/options.txt" ${OPTIONS_DEFAULTS} <<'PY'
import os, sys

path, pairs = sys.argv[1], sys.argv[2:]
# Split on the first colon only: plenty of values hold one themselves, e.g.
# "key_key.attack:key.mouse.0".
wanted = dict(p.split(":", 1) for p in pairs)

lines = []
if os.path.exists(path):
    with open(path) as f:
        lines = f.read().splitlines()

seen = set()
for i, ln in enumerate(lines):
    k = ln.split(":", 1)[0]
    if k in wanted:
        seen.add(k)
        lines[i] = f"{k}:{wanted[k]}"

lines += [f"{k}:{v}" for k, v in wanted.items() if k not in seen]

tmp = path + ".tmp"
with open(tmp, "w") as f:
    f.write("\n".join(lines) + "\n")
os.replace(tmp, path)
PY

    printf '%s' "${OPTIONS_DEFAULTS}" > "${marker}"
    return 0
}

apply_options || true

# --- server list ----------------------------------------------------------
add_server() {
    mkdir -p -- "${MC_DIR}"
    python3 - "${MC_DIR}/servers.dat" "${SERVER}" "${SERVER_NAME}" <<'PY'
import os, struct, sys

path, ip, name = sys.argv[1], sys.argv[2], sys.argv[3]

END, BYTE, STRING, LIST, COMPOUND = 0, 1, 8, 9, 10

def read(buf):
    """Parse the subset of NBT that servers.dat uses."""
    pos = 0
    def u1():
        nonlocal pos; v = buf[pos]; pos += 1; return v
    def u2():
        nonlocal pos; v = struct.unpack_from(">H", buf, pos)[0]; pos += 2; return v
    def i4():
        nonlocal pos; v = struct.unpack_from(">i", buf, pos)[0]; pos += 4; return v
    def s():
        nonlocal pos; n = u2(); v = buf[pos:pos+n].decode("utf-8", "replace"); pos += n; return v
    def payload(t):
        nonlocal pos
        if t == BYTE:   return u1()
        if t == STRING: return s()
        if t == LIST:
            et, n = u1(), i4()
            return [payload(et) for _ in range(n)]
        if t == COMPOUND:
            out = {}
            while True:
                it = u1()
                if it == END: return out
                # Read the name before the payload: in "out[s()] = payload(it)"
                # Python evaluates the payload first, which would consume the
                # name's bytes and desync the stream.
                key = s()
                out[key] = payload(it)
        raise ValueError(f"unsupported tag {t}")
    if u1() != COMPOUND:
        raise ValueError("not a compound root")
    return s(), payload(COMPOUND)

def write(root_name, servers):
    out = bytearray()
    def s(v):
        b = v.encode("utf-8"); out.extend(struct.pack(">H", len(b))); out.extend(b)
    out.append(COMPOUND); s(root_name)
    out.append(LIST); s("servers")
    out.append(COMPOUND); out.extend(struct.pack(">i", len(servers)))
    for e in servers:
        for k, v in e.items():
            if isinstance(v, int) and not isinstance(v, bool):
                out.append(BYTE); s(k); out.append(v & 0xFF)
            else:
                out.append(STRING); s(k); s(str(v))
        out.append(END)
    out.append(END)
    return bytes(out)

root_name, servers = "", []
if os.path.exists(path):
    try:
        root_name, root = read(open(path, "rb").read())
        servers = root.get("servers", [])
    except Exception:
        servers = []                  # unparseable -> rebuild rather than lose the entry

for e in servers:                     # already listed? just refresh the name
    if e.get("ip") == ip:
        e["name"] = name
        break
else:
    servers.insert(0, {"name": name, "ip": ip, "acceptTextures": 1})

tmp = path + ".tmp"
with open(tmp, "wb") as f:
    f.write(write(root_name, servers))
os.replace(tmp, path)
print(f"servers.dat: {len(servers)} entr{'y' if len(servers)==1 else 'ies'}")
PY
}

if [ -n "${SERVER}" ]; then
    add_server >/dev/null
    ok "Server" "${SERVER} ${C_DIM}as '${SERVER_NAME}'${C_OFF}"
else
    # Piped into bash ("curl ... | bash") leaves $0 as "bash", so the obvious
    # "$0 <ip>" would be useless advice. Tell each caller how to re-run itself.
    if [ -f "$0" ]; then
        hint="$0 <ip>"
    else
        hint="curl -fsSL ${SCRIPT_URL} | bash -s -- <ip>"
    fi
    warn "No server address given -- add one later with:"
    note "${hint}"
fi

# --- open the launcher ----------------------------------------------------
if [ "${LAUNCH}" -ne 1 ]; then
    printf '\n' >&2
    note "Set up, not started (--no-launch)."
    printf '\n' >&2
    exit 0
fi

have() {
    local want="$1" a
    for a in "${PRISM_ARGS[@]+"${PRISM_ARGS[@]}"}"; do
        case "$a" in "$want"|"$want"=*) return 0 ;; esac
    done
    return 1
}

ARGS=()
have -d || have --dir || ARGS+=(-d "${DATA_DIR}")

LOGFILE="${DATA_DIR}/prism.log"
if command -v setsid >/dev/null; then
    setsid "${BIN}" "${ARGS[@]+"${ARGS[@]}"}" "${PRISM_ARGS[@]+"${PRISM_ARGS[@]}"}" \
        > "${LOGFILE}" 2>&1 < /dev/null &
else
    nohup "${BIN}" "${ARGS[@]+"${ARGS[@]}"}" "${PRISM_ARGS[@]+"${PRISM_ARGS[@]}"}" \
        > "${LOGFILE}" 2>&1 < /dev/null &
fi
PRISM_PID=$!
disown "${PRISM_PID}" 2>/dev/null || true

sleep 2
if ! kill -0 "${PRISM_PID}" 2>/dev/null && ! pgrep -f "${APPIMAGE_NAME}" >/dev/null 2>&1; then
    printf '\n' >&2
    warn "The launcher exited immediately. Last lines of ${LOGFILE}:"
    tail -n 5 -- "${LOGFILE}" 2>/dev/null | while IFS= read -r l; do note "${l}"; done
    exit 1
fi

printf '\n' >&2
step "PrismLauncher is running. You can close this terminal."
note "Pick \"${INSTANCE_NAME}\" and hit Launch."
printf '\n' >&2
