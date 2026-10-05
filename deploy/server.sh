#!/usr/bin/env bash
# Déploie le serveur multijoueur sur Google Cloud Run.
# Usage :  ./deploy/server.sh <ID_PROJET_GCP> [region]
set -euo pipefail
PROJECT="${1:?Usage: ./deploy/server.sh <ID_PROJET_GCP> [region]}"
REGION="${2:-europe-west1}"
SERVICE="game304-server"

gcloud config set project "$PROJECT"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com

# Les tables vivent en mémoire : UNE seule instance (sinon deux joueurs d'une même
# table pourraient tomber sur deux instances différentes). Affinité de session pour
# les WebSockets, délai max 1 h par connexion (le client se reconnecte ensuite).
gcloud run deploy "$SERVICE" \
  --source . \
  --region "$REGION" \
  --allow-unauthenticated \
  --port 8080 \
  --min-instances 0 \
  --max-instances 1 \
  --session-affinity \
  --timeout 3600 \
  --memory 512Mi

URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.url)')"
echo
echo "Serveur en ligne : $URL"
echo "Test santé       : curl $URL/health"
echo "Adresse WebSocket pour l'app : ${URL/https:/wss:}/ws"
