// Chat vocal : qui se relie à qui (logique pure, sans WebRTC).
// La liaison audio elle-même est vérifiée dans Chromium (micro simulé), voir
// CLAUDE.md §6 ; flutter_test n'a pas de moteur WebRTC.
import 'package:flutter_test/flutter_test.dart';
import 'package:game304/net/voice.dart';

void main() {
  test('voicePeers : joueurs connectés dans le vocal, sauf soi', () {
    final players = <Map>[
      {'voice': true, 'online': true},
      {'voice': false, 'online': true, 'bot': true},
      {'voice': true, 'online': true},
      {'voice': true, 'online': false}, // déconnecté
    ];
    expect(voicePeers(0, players), {2});
    expect(voicePeers(2, players), {0});
    expect(voicePeers(1, players), {0, 2});
  });

  test('callsFirst : une seule offre par paire (le plus petit siège)', () {
    for (var a = 0; a < 4; a++) {
      for (var b = 0; b < 4; b++) {
        if (a == b) continue;
        expect(callsFirst(a, b) != callsFirst(b, a), isTrue,
            reason: 'exactement un des deux appelle ($a, $b)');
      }
    }
  });
}
