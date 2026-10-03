# Serveur multijoueur 304 -> binaire natif, image légère pour Cloud Run.
# Étape 1 : compilation (l'image Flutter fournit Dart + résout pubspec.yaml).
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
COPY lib ./lib
COPY bin ./bin
RUN flutter pub get
# bin/server.dart n'importe que le moteur et les bots (Dart pur) : pas de Flutter dans le binaire.
RUN dart compile exe bin/server.dart -o /out/server

# Étape 2 : exécution
FROM debian:bookworm-slim
COPY --from=build /out/server /server
ENV PORT=8080
EXPOSE 8080
CMD ["/server"]
