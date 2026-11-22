#!/usr/bin/env bash
# Assimilis Node for Linux and macOS: lend this computer's RAM (and GPU) to Assimilis Mobile's
# Devices & RAM pool, or host a big model here using phones and other PCs as extra RAM.
#
#   worker (default):  ./assimilis-node.sh
#   GPU worker:        BACKEND=vulkan ./assimilis-node.sh       (Linux; macOS uses Metal automatically)
#   host a model:      MODE=host MODEL=~/models/big.gguf WORKERS=192.168.1.20:50052,192.168.1.21:50052 ./assimilis-node.sh
#
# Uses llama.cpp release b11157, the same engine version as the app (RPC protocol rpc7).
# SECURITY: the worker has no password. Only run it on your own Wi-Fi or over Tailscale.
set -euo pipefail
RELEASE=b11157
MODE=${MODE:-worker}
BACKEND=${BACKEND:-cpu}
PORT=${PORT:-50052}
HOST_PORT=${HOST_PORT:-8080}
OS=$(uname -s); ARCH=$(uname -m)

case "$OS-$ARCH-$BACKEND" in
  Darwin-arm64-*)        ASSET="llama-$RELEASE-bin-macos-arm64.tar.gz" ;;
  Darwin-x86_64-*)       ASSET="llama-$RELEASE-bin-macos-x64.tar.gz" ;;
  Linux-x86_64-vulkan)   ASSET="llama-$RELEASE-bin-ubuntu-vulkan-x64.tar.gz" ;;
  Linux-x86_64-cuda)     ASSET="llama-$RELEASE-bin-ubuntu-cuda-12.8-x64.tar.gz" ;;
  Linux-x86_64-*)        ASSET="llama-$RELEASE-bin-ubuntu-x64.tar.gz" ;;
  Linux-aarch64-vulkan)  ASSET="llama-$RELEASE-bin-ubuntu-vulkan-arm64.tar.gz" ;;
  Linux-aarch64-*)       ASSET="llama-$RELEASE-bin-ubuntu-arm64.tar.gz" ;;
  *) echo "Unsupported system: $OS $ARCH"; exit 1 ;;
esac

DIR="${XDG_DATA_HOME:-$HOME/.local/share}/assimilis-node/$RELEASE-$BACKEND"
if [ -z "$(find "$DIR" -name 'ggml-rpc-server*' -o -name 'rpc-server' 2>/dev/null | head -1)" ]; then
  echo "Downloading llama.cpp $RELEASE ($ASSET) from github.com/ggml-org/llama.cpp ..."
  mkdir -p "$DIR"
  curl -fL "https://github.com/ggml-org/llama.cpp/releases/download/$RELEASE/$ASSET" | tar -xz -C "$DIR"
fi
RPC=$(find "$DIR" -type f \( -name 'ggml-rpc-server' -o -name 'rpc-server' \) | head -1)
SERVER=$(find "$DIR" -type f -name 'llama-server' | head -1)
LIBDIR=$(dirname "$RPC")
export LD_LIBRARY_PATH="$LIBDIR:${LD_LIBRARY_PATH:-}" DYLD_LIBRARY_PATH="$LIBDIR:${DYLD_LIBRARY_PATH:-}"

if [ "$OS" = Darwin ]; then
  IPS=$(ifconfig | awk '/inet /{print $2}' | grep -v '^127\.')
  FREE_MB=$(( $(sysctl -n hw.memsize) / 1048576 ))
else
  IPS=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' || true)
  FREE_MB=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
fi

if [ "$MODE" = host ]; then
  [ -f "${MODEL:-}" ] || { echo "Set MODEL=/path/to/model.gguf"; exit 1; }
  echo; echo "ASSIMILIS NODE · HOST  ($MODEL)"
  for ip in $IPS; do echo "  A's brain base URL:  http://$ip:$HOST_PORT/v1"; done
  ARGS=(-m "$MODEL" --host 0.0.0.0 --port "$HOST_PORT" -ngl 99)
  [ -n "${WORKERS:-}" ] && ARGS+=(--rpc "$WORKERS")
  exec "$SERVER" "${ARGS[@]}"
fi

# Announce on the network like a phone worker, so the app's "Scan" finds it.
NAME="Assimilis $(hostname -s)"
TXT=(ram="$FREE_MB" bw=20.0 model="$(hostname -s)" v=rpc7 id="node-$(hostname -s)")
if command -v dns-sd >/dev/null; then
  dns-sd -R "$NAME" _privatelm._tcp local "$PORT" "${TXT[@]}" >/dev/null 2>&1 &
  ANNOUNCE=$!
elif command -v avahi-publish-service >/dev/null; then
  avahi-publish-service "$NAME" _privatelm._tcp "$PORT" "${TXT[@]}" >/dev/null 2>&1 &
  ANNOUNCE=$!
else
  ANNOUNCE=""
  echo "(Install avahi-utils to be found by Scan; Add manually works without it.)"
fi
trap '[ -n "$ANNOUNCE" ] && kill $ANNOUNCE 2>/dev/null' EXIT

echo; echo "ASSIMILIS NODE · RAM WORKER  ($(hostname -s), about $FREE_MB MB free)"
echo "On the phone: Devices & RAM > Scan, or Add manually:"
for ip in $IPS; do echo "    $ip:$PORT"; done
echo "Keep this running while you use the model. Ctrl+C to stop."
THREADS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
"$RPC" -H 0.0.0.0 -p "$PORT" -c -t "$THREADS"
