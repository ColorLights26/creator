import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scene_compositor/scene_compositor.dart';

import 'adjustment_session.dart';

const adjustmentsAccent = Color(0xFF73F572);

/// One modifier as a control: a bar for sliders and steps, chips for a
/// choice, a switch for a toggle. Every whole step clicks.
class ModifierRow extends StatelessWidget {
  const ModifierRow({
    required this.modifier,
    required this.value,
    required this.onStart,
    required this.onChanged,
    super.key,
  });

  final CreatorModifier modifier;
  final double value;

  /// Called before a change so it can be undone.
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final original = modifier.value.toDouble();
    switch (modifier.kind) {
      case CreatorModifierKind.toggle:
        return AdjustmentLabeled(
          label: modifier.label,
          trailing: Switch(
            value: value == 1,
            activeThumbColor: adjustmentsAccent,
            onChanged: (on) {
              HapticFeedback.selectionClick();
              onStart();
              onChanged(on ? 1 : 0);
            },
          ),
        );
      case CreatorModifierKind.choice:
        return AdjustmentLabeled(
          label: modifier.label,
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (var index = 0; index < modifier.options.length; index++)
                ChoiceChip(
                  key: ValueKey('adjustments-modifier-${modifier.id}-$index'),
                  label: Text(modifier.options[index]),
                  selected: value.toInt() == index,
                  selectedColor: adjustmentsAccent.withValues(alpha: .25),
                  onSelected: (_) {
                    if (value.toInt() == index) return;
                    HapticFeedback.selectionClick();
                    onStart();
                    onChanged(index.toDouble());
                  },
                ),
            ],
          ),
        );
      case CreatorModifierKind.slider:
      case CreatorModifierKind.steps:
        return AdjustmentSlider(
          label: modifier.label,
          value: value,
          lower: modifier.lower,
          upper: modifier.upper,
          original: original,
          steps: modifier.kind == CreatorModifierKind.steps,
          onStart: onStart,
          onChanged: onChanged,
        );
    }
  }
}

/// A bar with a mark on the original value. Numbers appear only while the
/// finger moves it (always for whole steps, which are counts).
class AdjustmentSlider extends StatefulWidget {
  const AdjustmentSlider({
    required this.label,
    required this.value,
    required this.lower,
    required this.upper,
    required this.original,
    required this.onStart,
    required this.onChanged,
    this.steps = false,
    super.key,
  });

  final String label;
  final double value, lower, upper, original;
  final bool steps;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;

  @override
  State<AdjustmentSlider> createState() => _AdjustmentSliderState();
}

class _AdjustmentSliderState extends State<AdjustmentSlider> {
  bool _dragging = false;

  void _change(double next) {
    final value = widget.steps ? next.roundToDouble() : next;
    if (value == widget.value) return;
    final crossed =
        widget.steps ||
        (widget.value - widget.original).sign != (value - widget.original).sign;
    if (crossed) HapticFeedback.selectionClick();
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final span = widget.upper - widget.lower;
    final mark = span <= 0 ? 0.0 : (widget.original - widget.lower) / span;
    return AdjustmentLabeled(
      label: widget.label,
      value:
          widget.steps
              ? widget.value.toInt().toString()
              : _dragging
              ? sliderText(widget.lower, widget.upper, widget.value)
              : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment(mark * 2 - 1, 0),
                child: Container(
                  width: 2,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ),
          Slider(
            value: widget.value.clamp(widget.lower, widget.upper),
            min: widget.lower,
            max: widget.upper,
            divisions: widget.steps ? span.toInt() : null,
            activeColor: adjustmentsAccent,
            onChangeStart: (_) {
              setState(() => _dragging = true);
              widget.onStart();
            },
            onChanged: _change,
            onChangeEnd: (_) => setState(() => _dragging = false),
          ),
        ],
      ),
    );
  }
}

class AdjustmentLabeled extends StatelessWidget {
  const AdjustmentLabeled({
    required this.label,
    this.value,
    this.child,
    this.trailing,
    super.key,
  });

  final String label;
  final String? value;
  final Widget? child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (value case final String text)
                Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: adjustmentsAccent,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              if (trailing case final Widget widget) widget,
            ],
          ),
          if (child case final Widget widget) widget,
        ],
      ),
    );
  }
}
