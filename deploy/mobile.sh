#!/usr/bin/env bash
# Construit les paquets à envoyer aux stores.
# Usage :  ./deploy/mobile.sh <URL_WSS_DU_SERVEUR>
set -euo pipefail
SERVER_URL="${1:?Usage: ./deploy/mobile.sh <URL_WSS>}"
flutter build appbundle --release --dart-define=SERVER_URL="$SERVER_URL"
echo "Android : build/app/outputs/bundle/release/app-release.aab  -> Google Play Console"
if [[ "$(uname)" == "Darwin" ]]; then
  flutter build ipa --release --dart-define=SERVER_URL="$SERVER_URL"
  echo "iOS : build/ios/ipa/*.ipa  -> Transporter / App Store Connect"
else
  echo "iOS : à construire sur un Mac (Xcode requis)."
fi
