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
