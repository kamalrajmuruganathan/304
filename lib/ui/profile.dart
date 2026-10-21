// ============================================================================
// Profil du joueur : prénom + avatar (accueil). Le prénom pré-remplit le salon
// en ligne ; l'avatar est montré aux autres joueurs de la table.
// ============================================================================
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings.dart';

/// Pastille de l'accueil : avatar + prénom ; touche = modifier.
class ProfileChip extends StatelessWidget {
  const ProfileChip({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ValueListenableBuilder<String>(
      valueListenable: playerName,
      builder: (context, name, _) => ValueListenableBuilder<int>(
        valueListenable: avatar,
        builder: (context, av, _) => ActionChip(
          key: const ValueKey('profile'),
          avatar: avatarIcon(av, size: 24),
          label: Text(name.isEmpty ? l.profileSet : name),
          onPressed: () => showDialog<void>(
              context: context, builder: (_) => const ProfileDialog()),
        ),
      ),
    );
  }
}

class ProfileDialog extends StatefulWidget {
  const ProfileDialog({super.key});
  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  late final _name = TextEditingController(text: playerName.value);
  late int _av = avatar.value;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      scrollable: true,
      title: Text(l.profileTitle),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          key: const ValueKey('profile-name'),
          controller: _name,
          maxLength: kMaxName,
          decoration:
              InputDecoration(labelText: l.yourName, hintText: l.defaultPlayer),
        ),
        const SizedBox(height: 8),
        Text(l.profileAvatar),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < kAvatars.length; i++)
            InkWell(
              key: ValueKey('avatar-$i'),
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _av = i),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: i == _av ? Colors.white : Colors.transparent,
                      width: 2),
                ),
                child: avatarIcon(i, size: 38),
              ),
            ),
        ]),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.cancel)),
        FilledButton(
          key: const ValueKey('profile-save'),
          onPressed: () {
            setProfile(_name.text, _av);
            Navigator.of(context).pop();
          },
          child: Text(l.save),
        ),
      ],
    );
  }
}
