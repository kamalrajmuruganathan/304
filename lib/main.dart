import 'package:flutter/material.dart';
import 'ui/game_screen.dart';
import 'ui/online_screen.dart';

void main() => runApp(const Game304App());

class Game304App extends StatelessWidget {
  const Game304App({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: '304',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: base.colorScheme.copyWith(
          primary: const Color(0xFF2F81F7),
          secondary: const Color(0xFFD4A72C),
        ),
      ),
      // i18n : les fichiers lib/l10n/*.arb sont prêts. Câblage d'AppLocalizations
      // prévu en phase 2 (voir README, section Roadmap).
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('304',
                  style: TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFD4A72C))),
              const SizedBox(height: 4),
              Text('three-nought-four',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const GameScreen())),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                  child: Text('Partie rapide contre les bots'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const OnlineLobbyScreen())),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                  child: Text('Table privée entre amis'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
