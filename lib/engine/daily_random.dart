// Donne du jour : générateur et graine (Dart pur, sans Flutter : utilisable
// par les outils en ligne de commande et compilable en JavaScript).
import 'dart:math';

/// Générateur xorshift32 : uniquement des décalages et des « ou exclusifs »
/// masqués sur 32 bits, donc mêmes nombres sur toutes les plateformes.
class DailyRandom implements Random {
  int _x;
  DailyRandom(int seed) : _x = (seed ^ 0x9E3779B9) & 0xFFFFFFFF {
    if (_x == 0) _x = 0x2545F491;
    for (var i = 0; i < 8; i++) {
      _next();
    }
  }

  int _next() {
    var x = _x;
    x = (x ^ (x << 13)) & 0xFFFFFFFF;
    x = (x ^ (x >> 17)) & 0xFFFFFFFF;
    x = (x ^ (x << 5)) & 0xFFFFFFFF;
    _x = x;
    return x;
  }

  @override
  int nextInt(int max) => _next() % max;

  @override
  double nextDouble() => _next() / 4294967296.0;

  @override
  bool nextBool() => _next() & 1 == 1;
}

/// Jour (UTC) au format AAAA-MM-JJ : la même donne partout dans le monde.
String dayKey([DateTime? now]) {
  final d = (now ?? DateTime.now()).toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// Graine de la donne du jour [day] (AAAA-MM-JJ).
int dailySeed(String day) => int.parse(day.replaceAll('-', ''));
