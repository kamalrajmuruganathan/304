#!/usr/bin/env bash
# Construit l'app Flutter pour le web et la publie sur Firebase Hosting.
# Usage :  ./deploy/web.sh <ID_PROJET_FIREBASE> <URL_WSS_DU_SERVEUR>
#   ex.  ./deploy/web.sh mon-projet wss://game304-server-xxxx.a.run.app/ws
set -euo pipefail
PROJECT="${1:?Usage: ./deploy/web.sh <ID_PROJET_FIREBASE> <URL_WSS>}"
SERVER_URL="${2:?Usage: ./deploy/web.sh <ID_PROJET_FIREBASE> <URL_WSS>}"
flutter build web --release --dart-define=SERVER_URL="$SERVER_URL"
firebase deploy --only hosting --project "$PROJECT"
