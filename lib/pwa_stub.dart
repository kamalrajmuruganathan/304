// Hors web : pas d'installation de page web.
bool canInstall() => false;
bool standalone() => false;
Future<bool> install() async => false;
