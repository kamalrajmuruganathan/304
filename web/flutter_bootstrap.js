{{flutter_js}}
{{flutter_build_config}}

// Sans le service worker de Flutter (abandonné : il se désinscrit et
// effacerait le nôtre). Hors connexion : web/sw.js, enregistré par index.html.
_flutter.loader.load();
