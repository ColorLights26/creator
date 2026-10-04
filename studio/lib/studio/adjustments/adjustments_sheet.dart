import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'adjustment_session.dart';
import 'modifier_row.dart';
import 'palette_row.dart';
import 'personal_variations.dart';
import 'variation_chips.dart';

/// Opens Ajustes for [session]'s visual. It peeks at a third of the screen
/// with the looks and the dice so the visual stays in view; dragging it up
/// shows every control. Changes apply live through [session].
Future<void> showAdjustmentsSheet({
  required BuildContext context,
  required AdjustmentSession session,
  required PersonalVariations store,
  required VoidCallback onAnotherSeed,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  barrierColor: Colors.transparent,
  backgroundColor: const Color(0xF20F1715),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder:
      (_) => _AdjustmentsSheet(
        session: session,
        store: store,
        onAnotherSeed: onAnotherSeed,
      ),
);

class _AdjustmentsSheet extends StatefulWidget {
  const _AdjustmentsSheet({
    required this.session,
    required this.store,
    required this.onAnotherSeed,
  });

  final AdjustmentSession session;
  final PersonalVariations store;
  final VoidCallback onAnotherSeed;

  @override
  State<_AdjustmentsSheet> createState() => _AdjustmentsSheetState();
}

class _AdjustmentsSheetState extends State<_AdjustmentsSheet> {
  List<PersonalVariation> _personal = const [];

  AdjustmentSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPersonal());
  }

  Future<void> _loadPersonal() async {
    final saved = await widget.store.load(_session.visual);
    if (mounted) setState(() => _personal = saved);
  }

  Future<void> _savePersonal(List<PersonalVariation> next) async {
    setState(() => _personal = next);
    await widget.store.save(_session.visual, next);
  }

  void _saveCurrent() {
    final name = PersonalVariations.nextName(_personal);
    HapticFeedback.selectionClick();
    unawaited(
      _savePersonal([
        ..._personal,
        (name: name, values: _session.current, palette: _session.palette),
      ]),
    );
    _session.apply(name, _session.current, palette: _session.palette);
  }

  Future<void> _copyForAi(
    String name,
    AdjustmentValues values,
    List<int>? palette,
  ) async {
    await Clipboard.setData(
      ClipboardData(
        text: variationForAi(_session.visual, name, values, palette: palette),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Copiado. Pégalo a tu IA junto con la plantilla y el archivo del '
          'visual: quedará como variación.',
        ),
      ),
    );
  }

  Future<void> _personalMenu(PersonalVariation variation) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF16201D),
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (key, icon, label) in [
                  ('rename', Icons.edit_rounded, 'Renombrar'),
                  ('copy', Icons.auto_awesome_rounded, 'Copiar para la IA'),
                  ('delete', Icons.delete_outline_rounded, 'Borrar'),
                ])
                  ListTile(
                    key: ValueKey('adjustments-mine-action-$key'),
                    leading: Icon(icon, color: Colors.white70),
                    title: Text(label),
                    onTap: () => Navigator.of(context).pop(key),
                  ),
              ],
            ),
          ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'copy':
        await _copyForAi(variation.name, variation.values, variation.palette);
      case 'delete':
        await _savePersonal([
          for (final item in _personal)
            if (item.name != variation.name) item,
        ]);
      case 'rename':
        final name = await _askName(variation.name);
        if (name == null || name == variation.name) return;
        if (_personal.any((item) => item.name == name)) return;
        await _savePersonal([
          for (final item in _personal)
            item.name == variation.name
                ? (name: name, values: item.values, palette: item.palette)
                : item,
        ]);
    }
  }

  Future<String?> _askName(String current) async {
    final controller = TextEditingController(text: current);
    try {
      final name = await showDialog<String>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Nombre de la variación'),
              content: TextField(
                key: const ValueKey('adjustments-mine-name'),
                controller: controller,
                autofocus: true,
                maxLength: 20,
                onSubmitted: (value) => Navigator.of(context).pop(value),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(controller.text),
                  child: const Text('Guardar'),
                ),
              ],
            ),
      );
      final trimmed = name?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final visual = _session.visual;
        final values = _session.current;
        final basics = values.controls.toMap();
        final originalBasics = visual.controls.toMap();
        return DraggableScrollableSheet(
          key: const ValueKey('visual-adjustments'),
          initialChildSize: .33,
          minChildSize: .2,
          maxChildSize: .85,
          snap: true,
          snapSizes: const [.33, .75],
          expand: false,
          builder:
              (context, scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ajustes · ${visual.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        key: const ValueKey('adjustments-more'),
                        tooltip: 'Más',
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: Colors.white70,
                        ),
                        onSelected: (action) {
                          switch (action) {
                            case 'seed':
                              HapticFeedback.lightImpact();
                              widget.onAnotherSeed();
                            case 'copy':
                              unawaited(
                                _copyForAi(
                                  _session.chip == null ||
                                          _session.chip == originalChipName
                                      ? PersonalVariations.nextName(_personal)
                                      : _session.chip!,
                                  _session.current,
                                  _session.palette,
                                ),
                              );
                          }
                        },
                        itemBuilder:
                            (context) => const [
                              PopupMenuItem(
                                key: ValueKey('adjustments-seed'),
                                value: 'seed',
                                child: Text('Otra semilla'),
                              ),
                              PopupMenuItem(
                                key: ValueKey('adjustments-copy'),
                                value: 'copy',
                                child: Text('Copiar para la IA'),
                              ),
                            ],
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  VariationChips(
                    session: _session,
                    personal: _personal,
                    onSave:
                        _personal.length < personalVariationLimit &&
                                (_session.palette != null ||
                                    !sameAdjustmentValues(
                                      _session.current,
                                      _session.original,
                                    ))
                            ? _saveCurrent
                            : null,
                    onPersonalMenu:
                        (variation) => unawaited(_personalMenu(variation)),
                  ),
                  if (_session.recolorable) ...[
                    const SizedBox(height: 8),
                    PaletteRow(session: _session),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _action(
                        'adjustments-vary',
                        Icons.casino_outlined,
                        'Variar',
                        () {
                          HapticFeedback.lightImpact();
                          _session.vary();
                        },
                      ),
                      const SizedBox(width: 8),
                      _action(
                        'adjustments-surprise',
                        Icons.auto_awesome_rounded,
                        'Sorprender',
                        () {
                          HapticFeedback.mediumImpact();
                          _session.surprise();
                        },
                      ),
                      const Spacer(),
                      IconButton(
                        key: const ValueKey('adjustments-undo'),
                        tooltip: 'Deshacer',
                        onPressed:
                            _session.canUndo
                                ? () {
                                  HapticFeedback.selectionClick();
                                  _session.undo();
                                }
                                : null,
                        icon: const Icon(Icons.undo_rounded),
                        color: Colors.white,
                        disabledColor: Colors.white24,
                      ),
                    ],
                  ),
                  if (visual.modifiers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Text(
                        'Este visual no tiene modificadores propios. Los '
                        'visuales nuevos los traen: la plantilla le pide a la '
                        'IA que los cree.',
                        key: ValueKey('adjustments-no-modifiers'),
                        style: TextStyle(color: Colors.white60, height: 1.3),
                      ),
                    )
                  else ...[
                    _heading('MODIFICADORES'),
                    for (final modifier in visual.modifiers)
                      ModifierRow(
                        key: ValueKey('adjustments-modifier-${modifier.id}'),
                        modifier: modifier,
                        value: values.modifiers[modifier.id]!,
                        onStart: _session.beginEdit,
                        onChanged: (value) => _session.set(modifier.id, value),
                      ),
                  ],
                  if (_session.usedBasics.isNotEmpty) ...[
                    _heading('BÁSICOS'),
                    for (final (id, label, lowest) in adjustmentBasics)
                      if (_session.usedBasics.contains(id))
                        AdjustmentSlider(
                          key: ValueKey('adjustments-basic-$id'),
                          label: label,
                          value: basics[id]!,
                          lower: lowest,
                          upper: 2,
                          original: originalBasics[id]!,
                          onStart: _session.beginEdit,
                          onChanged: (value) => _session.set(id, value),
                        ),
                  ],
                ],
              ),
        );
      },
    );
  }
}

Widget _heading(String text) => Padding(
  padding: const EdgeInsets.only(top: 16, bottom: 4),
  child: Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
      color: Colors.white54,
    ),
  ),
);

Widget _action(String key, IconData icon, String label, VoidCallback onTap) =>
    OutlinedButton.icon(
      key: ValueKey(key),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 16, color: adjustmentsAccent),
      label: Text(label),
    );
