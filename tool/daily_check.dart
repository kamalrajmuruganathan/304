// Affiche les donnes du jour de quelques dates : le résultat doit être le même
// en Dart natif (téléphone) et compilé en JavaScript (web).
//   dart run tool/daily_check.dart
//   dart compile js tool/daily_check.dart -o /tmp/d.js && node /tmp/d.js
// ignore_for_file: avoid_print
import 'package:game304/engine/daily_random.dart';
import 'package:game304/engine/engine.dart';

void main() {
  for (final day in ['2026-01-01', '2026-10-21', '2027-02-28', '2030-12-31']) {
    final e = Engine(rng: DailyRandom(dailySeed(day)))..newHand();
    var redeals = 0;
    while (e.canRedeal() && redeals < 3) {
      e.redeal();
      redeals++;
    }
    print(
        '$day donneur ${e.dealer} : ${e.hands.map((h) => h.join(' ')).join(' | ')}'
        ' · reste ${e.deck.skip(16).take(16).join(' ')}');
  }
}
