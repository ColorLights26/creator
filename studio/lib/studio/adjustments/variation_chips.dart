import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'adjustment_session.dart';
import 'modifier_row.dart';
import 'personal_variations.dart';

/// Original · the author's variations · the team's saved looks · +.
/// A tap shows a look (the engine morphs into it); the active one is lit.
class VariationChips extends StatelessWidget {
  const VariationChips({
    required this.session,
    required this.personal,
    required this.onSave,
    required this.onPersonalMenu,
    super.key,
  });

  final AdjustmentSession session;
  final List<PersonalVariation> personal;
  final VoidCallback? onSave;
  final ValueChanged<PersonalVariation> onPersonalMenu;

  @override
  Widget build(BuildContext context) {
    final visual = session.visual;
    void show(String name, AdjustmentValues values) {
      if (session.chip == name && !session.comparing) return;
      HapticFeedback.selectionClick();
      session.apply(name, values);
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(
            key: const ValueKey('adjustments-chip-original'),
            label: originalChipName,
            selected: session.chip == originalChipName,
            onTap: () {
              if (session.chip == originalChipName && session.seed == null) {
                return;
              }
              HapticFeedback.selectionClick();
              session.resetToOriginal();
            },
          ),
          for (final variation in visual.variations)
            _chip(
              key: ValueKey('adjustments-chip-${variation.name}'),
              label: variation.name,
              selected: session.chip == variation.name,
              onTap: () => show(variation.name, variation.resolve(visual)),
            ),
          for (final variation in personal)
            _chip(
              key: ValueKey('adjustments-mine-${variation.name}'),
              label: variation.name,
              icon: Icons.bookmark_rounded,
              selected: session.chip == variation.name,
              onTap: () => show(variation.name, variation.values),
              onLongPress: () => onPersonalMenu(variation),
            ),
          if (onSave case final VoidCallback save)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                key: const ValueKey('adjustments-save'),
                tooltip: 'Guardar lo que ves',
                avatar: const Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: adjustmentsAccent,
                ),
                label: const Text('Guardar'),
                onPressed: save,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: ChoiceChip(
          key: key,
          avatar:
              icon == null ? null : Icon(icon, size: 16, color: Colors.white70),
          label: Text(label),
          selected: selected,
          selectedColor: adjustmentsAccent.withValues(alpha: .28),
          onSelected: (_) => onTap(),
        ),
      ),
    );
  }
}
