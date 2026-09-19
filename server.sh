#!/usr/bin/env bash
#
# Run the Paper server in ./server.
#
# Usage:
#   ./server.sh                  # run it
#   ./server.sh --port 25566     # arguments are forwarded to Paper
#   RAM=4G ./server.sh           # heap size (default 2G)
#
# Env overrides:
#   SERVER_ROOT   server directory  (default <script dir>/server)
#   RAM           heap size         (default 2G)
#   JAVA_BIN      java to use       (default: first Java >= 25 found)

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SERVER_ROOT="${SERVER_ROOT:-${HERE}/server}"
RAM="${RAM:-2G}"

PAPER_JAR="paper-26.2-124.jar"
PAPER_SHA256="274bbcb9807ad79a479617ce695a7c0686e652a8d1cabfd0e288d92a3ea29593"
PAPER_URL="https://fill-data.papermc.io/v1/objects/${PAPER_SHA256}/${PAPER_JAR}"

JAVA_MIN=25
JRE_URL="https://api.adoptium.net/v3/binary/latest/${JAVA_MIN}/ga/linux/x64/jre/hotspot/normal/eclipse"

JAR="${SERVER_ROOT}/${PAPER_JAR}"
JRE_DIR="${SERVER_ROOT}/.java"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "${SERVER_ROOT}" ] || die "no server dir at ${SERVER_ROOT}"

if command -v curl >/dev/null; then
    fetch() { curl -fL --retry 3 --retry-delay 2 -o "$2" "$1"; }
elif command -v wget >/dev/null; then
    fetch() { wget -O "$2" "$1"; }
else
    die "need curl or wget"
fi

# --- paper jar ------------------------------------------------------------
sha256_of() { sha256sum -- "$1" | cut -d' ' -f1; }

if [ ! -s "${JAR}" ] || [ "$(sha256_of "${JAR}")" != "${PAPER_SHA256}" ]; then
    log "Downloading ${PAPER_JAR}"
    fetch "${PAPER_URL}" "${JAR}.part" || { rm -f -- "${JAR}.part"; die "download failed"; }
    got="$(sha256_of "${JAR}.part")"
    [ "${got}" = "${PAPER_SHA256}" ] || {
        rm -f -- "${JAR}.part"
        die "checksum mismatch: expected ${PAPER_SHA256}, got ${got}"
    }
    mv -- "${JAR}.part" "${JAR}"
fi

# --- java -----------------------------------------------------------------
java_ok() {
    [ -x "$1" ] || return 1
    local v
    v="$("$1" -version 2>&1 | sed -n '1s/.*version "\([0-9]*\).*/\1/p')"
    [ -n "${v}" ] && [ "${v}" -ge "${JAVA_MIN}" ]
}

find_java() {
    [ -n "${JAVA_BIN:-}" ] && { java_ok "${JAVA_BIN}" || die "JAVA_BIN is not Java ${JAVA_MIN}+"; printf '%s' "${JAVA_BIN}"; return; }
    java_ok "${JRE_DIR}/bin/java" && { printf '%s' "${JRE_DIR}/bin/java"; return; }
    local c
    for c in "${JAVA_HOME:-/nonexistent}/bin/java" "$(command -v java || echo /nonexistent)" /usr/lib/jvm/*/bin/java; do
        java_ok "${c}" && { printf '%s' "${c}"; return; }
    done
    printf '' # nothing suitable
}

JAVA="$(find_java)"
if [ -z "${JAVA}" ]; then
    command -v tar >/dev/null || die "tar not found"
    log "Downloading Temurin JRE ${JAVA_MIN} (no Java ${JAVA_MIN}+ on this machine)"
    STAGING="$(mktemp -d "${SERVER_ROOT}/.jre-stage.XXXXXX")"
    trap 'rm -rf -- "${STAGING:-}"' EXIT
    fetch "${JRE_URL}" "${STAGING}/jre.tar.gz" || die "JRE download failed"
    tar -xzf "${STAGING}/jre.tar.gz" -C "${STAGING}" || die "JRE archive is corrupt -- rerun"
    # Temurin unpacks to a single top-level dir: jdk-25.../bin/java
    inner="$(find "${STAGING}" -type f -path '*/bin/java' -print -quit)"
    [ -n "${inner}" ] || die "java binary not found in JRE archive"
    rm -rf -- "${JRE_DIR}"
    mv -- "$(dirname -- "$(dirname -- "${inner}")")" "${JRE_DIR}"
    rm -rf -- "${STAGING}"; unset STAGING
    trap - EXIT
    JAVA="${JRE_DIR}/bin/java"
fi

# --- run ------------------------------------------------------------------
cd -- "${SERVER_ROOT}"
log "Starting Paper (${RAM} heap)"
exec "${JAVA}" \
    -Xms"${RAM}" -Xmx"${RAM}" \
    -XX:+UseG1GC -XX:MaxGCPauseMillis=200 \
    -XX:+ParallelRefProcEnabled -XX:+UnlockExperimentalVMOptions \
    -XX:+DisableExplicitGC -XX:+AlwaysPreTouch \
    -XX:G1HeapRegionSize=8M -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 \
    -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 \
    -XX:G1MixedGCLiveThresholdPercent=90 -XX:SurvivorRatio=32 \
    -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 \
    -Dfile.encoding=UTF-8 \
    -jar "${PAPER_JAR}" --nogui "$@"
