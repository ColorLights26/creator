import 'package:flutter/material.dart';

import 'modifier_row.dart';

/// The button above "Pruébalo con": opens Ajustes, says how many modifiers
/// of its own the visual has and which look is on screen.
class VisualAdjustmentsButton extends StatelessWidget {
  const VisualAdjustmentsButton({
    required this.modifierCount,
    required this.onPressed,
    this.look,
    super.key,
  });

  final int modifierCount;

  /// The look on screen when it is not the original ("Tormenta",
  /// "cambiados"), or null.
  final String? look;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final modified = look != null;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        key: const ValueKey('visual-adjustments-button'),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(
            color: modified ? adjustmentsAccent : Colors.white24,
          ),
          visualDensity: VisualDensity.compact,
        ),
        icon: Icon(
          Icons.tune_rounded,
          size: 16,
          color:
              modifierCount > 0 || modified
                  ? adjustmentsAccent
                  : Colors.white70,
        ),
        label: Text(
          [
            'Ajustes',
            if (modifierCount > 0)
              '$modifierCount ${modifierCount == 1 ? 'modificador' : 'modificadores'}',
            if (look case final String text) text,
          ].join(' · '),
        ),
      ),
    );
  }
}
