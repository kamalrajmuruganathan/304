# Déploiement

## Client web
```bash
flutter build web --release
# -> build/web  : héberger sur Firebase Hosting, Netlify, Cloud Storage+CDN, etc.
```

## Serveur multijoueur → Cloud Run (recommandé)

Le serveur (`bin/server.dart`) réutilise `lib/engine` + `lib/ai`, qui sont du **Dart pur**.
Pour un conteneur léger, on isole ces sources du SDK Flutter.

**Reco de structure (à faire une fois)** : extraire un paquet Dart pur `packages/engine`
(contenant `engine.dart` + `bots.dart`, sans dépendance Flutter), dont dépendent à la
fois l'app Flutter et un petit paquet serveur. Le serveur se compile alors sans Flutter :

```dockerfile
# Dockerfile (après extraction en paquet Dart pur)
FROM dart:stable AS build
WORKDIR /app
COPY . .
RUN dart pub get
RUN dart compile exe bin/server.dart -o /server
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /server /server
ENV PORT=8080
EXPOSE 8080
CMD ["/server"]
```

Déploiement :
```bash
gcloud run deploy game304-server \
  --source . --region europe-west1 \
  --allow-unauthenticated --port 8080
```
Cloud Run scale à zéro (coût quasi nul hors trafic). Health check : `GET /health`.

## Mobile
- **Android** : `flutter build appbundle` → Google Play Console (25 $ une fois).
- **iOS** : `flutter build ipa` → App Store Connect (Apple Developer, 99 $/an).

## Assets store
`assets/icon.svg` est le master de l'icône. Générer les PNG requis (1024, adaptatives
Android, etc.) avec un outil comme `flutter_launcher_icons`.
