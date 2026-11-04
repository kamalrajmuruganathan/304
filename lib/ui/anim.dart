import 'package:flutter/material.dart';

/// Distribution : la carte arrive du centre de la table (en haut) et
/// apparaît en fondu, en cascade selon sa position [index] dans la main.
/// À envelopper dans un widget à clé stable (la carte) : seules les cartes
/// nouvellement reçues s'animent.
class DealIn extends StatelessWidget {
  const DealIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  static const _step = 70, _move = 260;

  @override
  Widget build(BuildContext context) {
    final total = _move + _step * index;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(_step * index / total, 1, curve: Curves.easeOutCubic),
      builder: (_, t, ch) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, -90 * (1 - t)), child: ch),
      ),
      child: child,
    );
  }
}

/// Ramassage : le pli terminé reste visible, puis glisse vers le gagnant
/// ([toward] = alignement de son siège) en rétrécissant et en s'effaçant.
class GatherTo extends StatelessWidget {
  const GatherTo(
      {super.key,
      required this.toward,
      required this.duration,
      required this.child});
  final Alignment toward;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: const Interval(0.55, 1, curve: Curves.easeInCubic),
      builder: (_, t, ch) => Opacity(
        opacity: 1 - t,
        child: Transform.translate(
          offset: Offset(toward.x * 120, toward.y * 120) * t,
          child: Transform.scale(scale: 1 - 0.35 * t, child: ch),
        ),
      ),
      child: child,
    );
  }
}

/// Lueur qui « respire » autour de [child] tant que [active] (thèmes
/// Cristal / Nuit : c'est à vous de jouer). [animate] faux : lueur fixe.
class PulseGlow extends StatefulWidget {
  const PulseGlow(
      {super.key,
      required this.active,
      required this.animate,
      required this.color,
      required this.radius,
      required this.child});
  final bool active, animate;
  final Color color;
  final double radius;
  final Widget child;

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));

  void _sync() {
    final run = widget.active && widget.animate;
    if (run && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!run && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PulseGlow old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, ch) {
        final a = widget.active ? 0.30 + 0.35 * _c.value : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: a == 0
                ? null
                : [
                    BoxShadow(
                        color: widget.color.withValues(alpha: a),
                        blurRadius: 18 + 18 * _c.value,
                        spreadRadius: 1)
                  ],
          ),
          child: ch,
        );
      },
      child: widget.child,
    );
  }
}

/// Éclat lumineux (pli gagné par votre équipe, thèmes Cristal / Nuit) :
/// un anneau qui s'agrandit et s'efface, une seule fois.
class GlowBurst extends StatelessWidget {
  const GlowBurst({super.key, required this.color, required this.duration});
  final Color color;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => CustomPaint(
          painter: _BurstPainter(color, t),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.color, this.t);
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide * (0.15 + 0.45 * t);
    final fade = 1 - t;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = color.withValues(alpha: 0.55 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * fade + 1
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(
        c,
        r * 0.6,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: 0.30 * fade),
            color.withValues(alpha: 0)
          ]).createShader(Rect.fromCircle(center: c, radius: r * 0.6)));
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.color != color;
}
