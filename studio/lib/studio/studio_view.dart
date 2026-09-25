import 'package:flutter/material.dart';

class StudioVisualItem {
  const StudioVisualItem({
    required this.id,
    required this.name,
    required this.thumbnail,
    this.description = '',
    this.details = '',
  });
  final String id;
  final String name;
  final Widget thumbnail;
  final String description;
  final String details;
}

class StudioSignalSource {
  const StudioSignalSource({
    required this.id,
    required this.name,
    required this.description,
  });
  final String id;
  final String name;
  final String description;
}

class StudioView extends StatelessWidget {
  const StudioView({
    required this.visuals,
    required this.sources,
    required this.selectedVisualId,
    required this.selectedSourceId,
    required this.textureId,
    required this.preview,
    required this.playing,
    required this.reactive,
    required this.reactionEnabled,
    required this.loading,
    required this.error,
    required this.onSelectVisual,
    required this.onSelectSource,
    required this.onTogglePlaying,
    required this.onReactiveChanged,
    required this.onReload,
    required this.onViewportChanged,
    super.key,
  });

  final List<StudioVisualItem> visuals;
  final List<StudioSignalSource> sources;
  final String? selectedVisualId;
  final String selectedSourceId;
  final int? textureId;
  final Widget? preview;
  final bool playing;
  final bool reactive;
  final bool reactionEnabled;
  final bool loading;
  final String? error;
  final ValueChanged<String> onSelectVisual;
  final ValueChanged<String> onSelectSource;
  final VoidCallback onTogglePlaying;
  final ValueChanged<bool> onReactiveChanged;
  final VoidCallback onReload;
  final void Function(Size size, double pixelRatio) onViewportChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.8),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Visual Studio'),
        actions: [
          IconButton(
            tooltip: 'Recargar visuales',
            onPressed: loading ? null : onReload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _preview(context),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 72, 16, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                return Align(
                  alignment:
                      wide ? Alignment.bottomRight : Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: wide ? 340 : 520,
                      maxHeight: constraints.maxHeight * (wide ? 1 : 0.5),
                    ),
                    child: Material(
                      key: const ValueKey('studio-controls-overlay'),
                      color: theme.colorScheme.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(24),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _controls(context),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      backgroundColor: theme.colorScheme.surface,
    );
  }

  Widget _preview(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final nativeTextureId = textureId;
    final problem = error;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onViewportChanged(size, pixelRatio);
        });
        return ColoredBox(
          key: const ValueKey('visual-surface'),
          color: colors.surfaceContainerLowest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (preview case final Widget surface)
                surface
              else if (nativeTextureId != null)
                Texture(
                  key: ValueKey(nativeTextureId),
                  textureId: nativeTextureId,
                  filterQuality: FilterQuality.low,
                ),
              if (preview == null &&
                  nativeTextureId == null &&
                  problem == null &&
                  !loading)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      visuals.isEmpty
                          ? 'La lista de visuales está vacía.'
                          : 'Prepara un visual para empezar.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              if (problem != null)
                ColoredBox(
                  color: colors.surfaceContainerLowest.withValues(alpha: 0.95),
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: colors.error,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No se pudo mostrar el visual',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            problem,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (loading)
                Center(
                  child: Semantics(
                    label: 'Preparando visual',
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _controls(BuildContext context) {
    final theme = Theme.of(context);
    final source = sources.firstWhere((item) => item.id == selectedSourceId);
    final selected =
        visuals.where((visual) => visual.id == selectedVisualId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('TUS VISUALES', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        _selector(
          context,
          key: const ValueKey('visual-selector'),
          label: 'Visual',
          value: selectedVisualId,
          items: [
            for (final visual in visuals)
              DropdownMenuItem(
                value: visual.id,
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: visual.thumbnail,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        visual.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: loading ? null : onSelectVisual,
        ),
        if (selected != null) ...[
          const SizedBox(height: 10),
          Text(selected.details, style: theme.textTheme.labelSmall),
          if (selected.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(selected.description, style: theme.textTheme.bodySmall),
          ],
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('play-button'),
          onPressed:
              loading || (preview == null && textureId == null) || error != null
                  ? null
                  : onTogglePlaying,
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          label: Text(playing ? 'Pausar' : 'Reproducir'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 24),
        Text('PRUEBA DE MOVIMIENTO', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        _selector(
          context,
          key: const ValueKey('source-selector'),
          label: 'Señal de prueba',
          value: selectedSourceId,
          items: [
            for (final item in sources)
              DropdownMenuItem(value: item.id, child: Text(item.name)),
          ],
          onChanged: loading ? null : onSelectSource,
        ),
        const SizedBox(height: 8),
        Text(source.description, style: theme.textTheme.bodySmall),
        SwitchListTile.adaptive(
          key: const ValueKey('reaction-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Reaccionar a la señal'),
          value: reactive,
          onChanged: loading || !reactionEnabled ? null : onReactiveChanged,
        ),
      ],
    );
  }

  Widget _selector(
    BuildContext context, {
    required Key key,
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String>? onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: key,
            isExpanded: true,
            value: value,
            hint: Text(label),
            borderRadius: BorderRadius.circular(14),
            items: items,
            onChanged:
                onChanged == null
                    ? null
                    : (value) {
                      if (value != null) onChanged(value);
                    },
          ),
        ),
      ),
    );
  }
}
