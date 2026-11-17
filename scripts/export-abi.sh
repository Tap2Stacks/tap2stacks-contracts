#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
BACKEND_ABI_DIR="$ROOT_DIR/../tap2stacks-backend/src/abi"
WEB_ABI_DIR="$ROOT_DIR/../tap2stacks-web/src/contracts/abi"

mkdir -p "$BACKEND_ABI_DIR" "$WEB_ABI_DIR"

for name in TestUSDC Tap2StacksVault ProofAnchor; do
  src="$OUT_DIR/${name}.sol/${name}.json"
  jq '.abi' "$src" > "$BACKEND_ABI_DIR/${name}.json"
  cp "$BACKEND_ABI_DIR/${name}.json" "$WEB_ABI_DIR/${name}.json"
done
