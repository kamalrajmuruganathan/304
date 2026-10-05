import 'package:audioplayers/audioplayers.dart';
import 'settings.dart';

/// Sons du prototype (bips synthétisés, mêmes fréquences et durées) :
/// carte posée, pli ramassé, donne gagnée, donne perdue.
enum Sfx { card, trick, win, lose }

final Map<Sfx, AudioPlayer> _players = {};

/// Joue un son si le son est activé. Ne lève jamais d'erreur (navigateur
/// sans geste utilisateur, plateforme sans audio, tests…).
Future<void> playSfx(Sfx s) async {
  if (!soundEnabled) return;
  try {
    final p = _players[s] ??= AudioPlayer();
    await p.stop();
    await p.play(AssetSource('sounds/${s.name}.wav'),
        mode: PlayerMode.lowLatency);
  } catch (_) {}
}
