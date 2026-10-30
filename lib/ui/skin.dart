// ============================================================================
// Thèmes de l'appli (comme le jeu Thaayam) : Cristal (par défaut), Temple,
// Nuit, Bois. Un thème fixe toutes les couleurs des écrans (accueil, table,
// salon, résultats) et l'ambiance du fond. Les cartes restent blanches
// (lisibilité) ; leur dos se choisit à part. Préférence `theme304`.
// ============================================================================
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings.dart' show feltColors;

/// Codes des thèmes, dans l'ordre d'affichage.
const kSkins = ['cristal', 'temple', 'nuit', 'bois'];
const kDefaultSkin = 'cristal';

/// Thème choisi (mémorisé sous `theme304`).
final ValueNotifier<String> skinCode = ValueNotifier<String>(kDefaultSkin);

Future<void> loadSkin() async {
  try {
    final v = (await SharedPreferences.getInstance()).getString('theme304');
    if (v != null && kSkins.contains(v)) skinCode.value = v;
  } catch (_) {}
}

Future<void> setSkin(String v) async {
  if (!kSkins.contains(v)) return;
  skinCode.value = v;
  try {
    await (await SharedPreferences.getInstance()).setString('theme304', v);
  } catch (_) {}
}

/// Palette d'un thème. `accent` remplace l'or de l'ancienne table royale
/// (bordures actives, valeurs mises en avant) ; `glow` : halo lumineux des
/// thèmes Cristal et Nuit (null : pas de halo).
class Skin {
  const Skin({
    required this.code,
    required this.dark,
    required this.bg,
    required this.surface,
    required this.text,
    required this.dim,
    required this.accent,
    required this.accentDim,
    required this.onAccent,
    required this.line,
    required this.bar,
    required this.panel,
    required this.dialog,
    required this.pod,
    required this.table,
    required this.tableBorder,
    required this.glow,
    required this.accent2,
  });

  final String code;
  final bool dark;
  final Color bg, surface, text, dim, accent, accentDim, onAccent, line;

  /// Dégradés (haut, bas) : tableau des scores, panneau du bas.
  final (Color, Color) bar, panel;
  final Color dialog, pod;

  /// Table : (centre, bord) ; null = tapis choisi dans les réglages (Bois).
  final (Color, Color)? table;
  final Color tableBorder;
  final Color? glow;

  /// 2e couleur des dégradés de boutons (néon violet de Nuit…).
  final Color accent2;

  /// Couleurs de la table (thème Bois : tapis choisi).
  (Color, Color) get tableColors => table ?? feltColors;

  bool get luminous => glow != null;

  /// Ombre lumineuse (Cristal, Nuit) ou ombre portée.
  List<BoxShadow> shadow({double blur = 16, double opacity = 0.35}) => glow !=
          null
      ? [BoxShadow(color: glow!.withValues(alpha: opacity), blurRadius: blur)]
      : [
          BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.5 : 0.18),
              blurRadius: blur * 0.6,
              offset: const Offset(0, 4))
        ];
}

const _cristal = Skin(
  code: 'cristal',
  dark: true,
  bg: Color(0xFF04070B),
  surface: Color(0xFF0E1822),
  text: Color(0xFFE9F3FB),
  dim: Color(0xFF8EA7B9),
  accent: Color(0xFF7FDCFF),
  accentDim: Color(0xFF2C6F93),
  onAccent: Color(0xFF03121C),
  line: Color(0x475FD4FF),
  bar: (Color(0xFF0A141E), Color(0xFF05090E)),
  panel: (Color(0xFF081018), Color(0xFF04070B)),
  dialog: Color(0xF00B1620),
  pod: Color(0xB30E1822),
  table: (Color(0xFF123A52), Color(0xFF081018)),
  tableBorder: Color(0xFF5FD4FF),
  glow: Color(0xFF5FD4FF),
  accent2: Color(0xFF2F9FD6),
);

const _temple = Skin(
  code: 'temple',
  dark: false,
  bg: Color(0xFFE9DFCB),
  surface: Color(0xFFF6EFE1),
  text: Color(0xFF2A2118),
  dim: Color(0xFF6F5F48),
  accent: Color(0xFF9A6A12),
  accentDim: Color(0xFFC9B48E),
  onAccent: Color(0xFFFFF8E6),
  line: Color(0xFFC9B48E),
  bar: (Color(0xFFF6EFE1), Color(0xFFE6DAC3)),
  panel: (Color(0xFFF3E9D6), Color(0xFFE6DAC3)),
  dialog: Color(0xFFF6EFE1),
  pod: Color(0xCCF6EFE1),
  table: (Color(0xFFB39468), Color(0xFF8D7556)), // grès
  tableBorder: Color(0xFFD9A520),
  glow: null,
  accent2: Color(0xFFD9A520),
);

const _nuit = Skin(
  code: 'nuit',
  dark: true,
  bg: Color(0xFF06020D),
  surface: Color(0xFF160A2A),
  text: Color(0xFFF6E9FF),
  dim: Color(0xFFB49CCC),
  accent: Color(0xFFFF4FD8),
  accentDim: Color(0xFF7A3CFF),
  onAccent: Color(0xFF1A0517),
  line: Color(0x667A3CFF),
  bar: (Color(0xFF140A26), Color(0xFF07030F)),
  panel: (Color(0xFF120822), Color(0xFF06020D)),
  dialog: Color(0xF0140A26),
  pod: Color(0xB3160A2A),
  table: (Color(0xFF2A0F45), Color(0xFF0C0618)),
  tableBorder: Color(0xFFFF4FD8),
  glow: Color(0xFFFF4FD8),
  accent2: Color(0xFF7A3CFF),
);

/// Bois : l'ancienne table « royale » (or, bois, tapis au choix).
const _bois = Skin(
  code: 'bois',
  dark: true,
  bg: Color(0xFF160A06),
  surface: Color(0xFF211208),
  text: Color(0xFFF3EAD6),
  dim: Color(0xFFC9B48A),
  accent: Color(0xFFE3C565),
  accentDim: Color(0xFFA5822F),
  onAccent: Color(0xFF2A1C06),
  line: Color(0xFF5A3D2E),
  bar: (Color(0xFF241009), Color(0xFF160A06)),
  panel: (Color(0xFF1C0F09), Color(0xFF140A06)),
  dialog: Color(0xFF211208),
  pod: Color(0x52000000),
  table: null,
  tableBorder: Color(0xFFA5822F),
  glow: null,
  accent2: Color(0xFFA5822F),
);

const _skins = {
  'cristal': _cristal,
  'temple': _temple,
  'nuit': _nuit,
  'bois': _bois
};

Skin skinOf(String code) => _skins[code] ?? _cristal;

/// Thème en cours.
Skin get sk => skinOf(skinCode.value);

/// Icône de chaque thème (pas d'emoji : rendu fiable sur le web).
IconData skinIcon(String code) => switch (code) {
      'temple' => Icons.temple_hindu,
      'nuit' => Icons.nightlight_round,
      'bois' => Icons.forest,
      _ => Icons.diamond,
    };

/// ThemeData Material du thème (accueil, salon, fenêtres).
ThemeData skinTheme(Skin s) {
  final base = ThemeData(
    brightness: s.dark ? Brightness.dark : Brightness.light,
    useMaterial3: true,
    fontFamilyFallback: const ['Suits'],
  );
  return base.copyWith(
    scaffoldBackgroundColor: s.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: s.accent,
      onPrimary: s.onAccent,
      secondary: s.accent2,
      surface: s.surface,
      onSurface: s.text,
      outline: s.line,
    ),
    appBarTheme: AppBarTheme(
        backgroundColor: s.bar.$1, foregroundColor: s.text, elevation: 0),
    dialogTheme: DialogThemeData(backgroundColor: s.dialog),
    textTheme: base.textTheme.apply(bodyColor: s.text, displayColor: s.text),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: s.accent,
      backgroundColor: s.surface,
      side: BorderSide(color: s.line),
      checkmarkColor: s.onAccent,
      labelStyle: TextStyle(color: s.text),
      secondaryLabelStyle: TextStyle(color: s.onAccent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.dark ? Colors.black.withValues(alpha: 0.35) : s.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: s.line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: s.accent, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        foregroundColor: s.text,
        backgroundColor: s.surface.withValues(alpha: s.dark ? 0.75 : 1),
        side: BorderSide(color: s.line),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: s.surface,
      contentTextStyle: TextStyle(color: s.text),
    ),
  );
}

/// Fond d'écran du thème : Cristal / Nuit = halo au plafond, bandeau LED
/// courbe et sol quadrillé en perspective ; Temple = pierre claire et fines
/// lignes ; Bois = uni.
class Ambiance extends StatelessWidget {
  const Ambiance({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: skinCode,
      builder: (context, code, _) {
        final s = skinOf(code);
        return DecoratedBox(
          decoration: BoxDecoration(color: s.bg),
          child: Stack(children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _AmbiancePainter(s)),
              ),
            ),
            child,
          ]),
        );
      },
    );
  }
}

class _AmbiancePainter extends CustomPainter {
  _AmbiancePainter(this.s);
  final Skin s;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (s.code == 'temple') {
      // pierre : fines lignes, comme des dalles
      final p = Paint()
        ..color = const Color(0x14806A40)
        ..strokeWidth = 1;
      for (var x = 0.0; x < w; x += 44) {
        canvas.drawLine(Offset(x, 0), Offset(x, h), p);
      }
      for (var y = 0.0; y < h; y += 44) {
        canvas.drawLine(Offset(0, y), Offset(w, y), p);
      }
      return;
    }
    final glow = s.glow;
    if (glow == null) return;
    final halo =
        s.code == 'nuit' ? const Color(0xFFFF4FD8) : const Color(0xFF288CC8);
    final led =
        s.code == 'nuit' ? const Color(0xFFFF8AE5) : const Color(0xFFA0E6FF);
    final grid =
        s.code == 'nuit' ? const Color(0xFFB678FF) : const Color(0xFF5FD4FF);
    // halo au plafond
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h * 0.45),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topCenter,
          radius: 0.9,
          colors: [halo.withValues(alpha: 0.30), halo.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, -h * 0.2, w, h * 0.65)),
    );
    // bandeau LED courbe
    final arc = Path()
      ..moveTo(w * 0.12, -4)
      ..quadraticBezierTo(w / 2, 48, w * 0.88, -4);
    canvas.drawPath(
        arc,
        Paint()
          ..color = led.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawPath(
        arc,
        Paint()
          ..color = led.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    // sol brillant quadrillé en perspective
    final floor = h * 0.62;
    final vanish = Offset(w / 2, floor - h * 0.5);
    final line = Paint()
      ..color = grid.withValues(alpha: 0.13)
      ..strokeWidth = 1;
    for (var k = -8; k <= 8; k++) {
      final xb = w / 2 + k * (w / 5);
      final t = (floor - vanish.dy) / (h - vanish.dy);
      canvas.drawLine(
          Offset(vanish.dx + (xb - vanish.dx) * t, floor), Offset(xb, h), line);
    }
    for (var i = 1; i <= 9; i++) {
      final y = floor + (h - floor) * math.pow(i / 9, 1.8);
      canvas.drawLine(
          Offset(0, y),
          Offset(w, y),
          Paint()
            ..color = grid.withValues(alpha: 0.04 + 0.1 * i / 9)
            ..strokeWidth = 1);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, floor, w, h - floor),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [grid.withValues(alpha: 0), grid.withValues(alpha: 0.12)],
        ).createShader(Rect.fromLTWH(0, floor, w, h - floor)),
    );
  }

  @override
  bool shouldRepaint(_AmbiancePainter old) => old.s.code != s.code;
}

/// Grand titre « 304 » de l'accueil, dans le style du thème.
class SkinTitle extends StatelessWidget {
  const SkinTitle({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // const : se reconstruit quand le thème change
    final s = sk;
    final glowShadow = s.glow == null
        ? const <Shadow>[]
        : [Shadow(color: s.glow!.withValues(alpha: 0.7), blurRadius: 22)];
    final title = Text('304',
        style: TextStyle(
          fontFamily: s.code == 'bois' ? null : 'Saira',
          fontSize: 72,
          fontWeight: s.code == 'bois' ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: s.code == 'bois' ? 0 : 14,
          color: switch (s.code) {
            'cristal' => const Color(0xFFF2F8FC),
            'nuit' => const Color(0xFFFDE6FF),
            'temple' => const Color(0xFF6B4A12),
            _ => const Color(0xFFD4A72C),
          },
          shadows: glowShadow,
        ));
    // dessous : fine ligne de lumière (Cristal, Nuit), points dorés (Temple)
    Widget under;
    if (s.glow != null) {
      under = Container(
        width: 170,
        height: 2,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          gradient: LinearGradient(colors: [
            Colors.transparent,
            s.code == 'nuit'
                ? const Color(0xFFFFB8F1)
                : const Color(0xFFBFF0FF),
            s.glow!,
            s.code == 'nuit'
                ? const Color(0xFFFFB8F1)
                : const Color(0xFFBFF0FF),
            Colors.transparent,
          ]),
          boxShadow: [
            BoxShadow(color: s.glow!.withValues(alpha: 0.9), blurRadius: 12)
          ],
        ),
      );
    } else if (s.code == 'temple') {
      under = Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 13; i++)
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Color(0xFFD9A520)),
          ),
      ]);
    } else {
      under = const SizedBox.shrink();
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      title,
      under,
    ]);
  }
}

/// Carte de réglages de l'accueil (verre fumé lumineux, pierre ou bois).
class SkinCard extends StatelessWidget {
  const SkinCard({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final s = sk;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: s.surface.withValues(alpha: s.dark ? 0.78 : 1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.line),
        gradient: s.dark
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.06),
                  s.surface.withValues(alpha: 0.78),
                ],
                stops: const [0, 0.45],
              )
            : null,
        boxShadow: s.shadow(blur: 14, opacity: 0.18),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.luminous ? title.toUpperCase() : title,
              style: TextStyle(
                color: s.luminous ? s.accent : s.accent,
                fontWeight: FontWeight.w600,
                letterSpacing: s.luminous ? 1.2 : 0,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ]),
    );
  }
}

/// Bouton principal de l'accueil : dégradé et halo du thème (verre éclairé
/// en Cristal, néon en Nuit, or en Temple et Bois), toute la largeur.
class SkinPrimaryButton extends StatelessWidget {
  const SkinPrimaryButton(
      {super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final s = sk;
    final colors = switch (s.code) {
      'cristal' => const [
          Color(0xFFE9F8FF),
          Color(0xFF8FDCFF),
          Color(0xFF2F9FD6)
        ],
      'nuit' => const [Color(0xFFFF4FD8), Color(0xFFB04BFF), Color(0xFF7A3CFF)],
      'temple' => const [
          Color(0xFFF2D488),
          Color(0xFFD9A520),
          Color(0xFF9A6A12)
        ],
      _ => const [Color(0xFFF0D98A), Color(0xFFE3C565), Color(0xFFA5822F)],
    };
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Ink(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors,
                stops: const [0, 0.45, 1],
              ),
              border: Border.all(color: colors.first),
              boxShadow: s.shadow(blur: 18, opacity: 0.45),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[
                  Icon(icon, color: s.onAccent),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: s.onAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
