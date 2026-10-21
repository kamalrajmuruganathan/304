#!/usr/bin/env bash
# Écrit build/web/precache.json : fichiers copiés par web/sw.js dès
# l'installation (appli jouable sans internet). Lancé après `flutter build web`.
set -euo pipefail
cd "${1:-build/web}"
find . -type f \
  ! -name '*.symbols' ! -name '.last_build_id' ! -name 'NOTICES' \
  ! -name 'flutter_service_worker.js' ! -name 'sw.js' ! -name 'precache.json' \
  ! -path './canvaskit/skwasm*' ! -path './canvaskit/wimp*' \
  ! -path './canvaskit/webparagraph/*' \
  | sed 's|^\./||' | sort \
  | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()], indent=0))' \
  > precache.json
echo "precache.json : $(grep -c '"' precache.json) fichiers"
