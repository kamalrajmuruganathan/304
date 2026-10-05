# Serveur multijoueur 304 -> binaire natif, image minimale pour Cloud Run.
# Étape 1 : compilation avec le SDK Dart seul (le serveur n'utilise que
# lib/engine et lib/ai, en Dart pur : pas besoin de Flutter).
FROM dart:stable AS build
WORKDIR /app
COPY deploy/server.pubspec.yaml ./pubspec.yaml
COPY lib/engine ./lib/engine
COPY lib/ai ./lib/ai
COPY bin ./bin
RUN dart pub get
RUN mkdir -p /out && dart compile exe bin/server.dart -o /out/server

# Étape 2 : exécution (bibliothèques système minimales fournies par l'image dart)
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /server
ENV PORT=8080
EXPOSE 8080
CMD ["/server"]
