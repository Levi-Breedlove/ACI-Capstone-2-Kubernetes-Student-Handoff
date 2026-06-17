#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDOFF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKDIR="${PHASE10_WORKDIR:-/tmp/phase10-student-handoff}"

PROD_ZIP="$HANDOFF_DIR/packages/phase-10-appointments-app.zip"
LAB_ZIP="$HANDOFF_DIR/packages/phase-10-appointments-app-lab.zip"

if [[ ! -f "$PROD_ZIP" || ! -f "$LAB_ZIP" ]]; then
  echo "Expected package zips under $HANDOFF_DIR/packages" >&2
  exit 1
fi

mkdir -p "$WORKDIR/production" "$WORKDIR/lab"

unzip -oq "$PROD_ZIP" -d "$WORKDIR/production"
unzip -oq "$LAB_ZIP" -d "$WORKDIR/lab"

echo "Extracted production package to: $WORKDIR/production"
echo "Extracted lab package to:        $WORKDIR/lab"
echo
echo "Use the production extraction for personal AWS account deployment."
