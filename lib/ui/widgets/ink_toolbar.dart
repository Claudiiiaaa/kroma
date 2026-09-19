import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kroma/models/tool.dart';
import 'package:kroma/providers/ink_provider.dart';

/// Barra flotante con las herramientas del lienzo.
///
/// Es un [ConsumerWidget] y no un widget normal porque necesita leer el estado
/// de Riverpod. Va separada del lienzo a propósito: así, cuando cambia la
/// herramienta activa, se reconstruye la barra pero **no** el lienzo, que es
/// mucho más caro de reconstruir.
class InkToolbar extends ConsumerWidget {
  const InkToolbar({super.key});

  /// Paleta fija de tinta.
  ///
  /// Son colores de bolígrafo y rotulador, no colores de interfaz: ninguno es
  /// negro puro ni de saturación máxima, porque sobre papel claro resultan
  /// duros y cansan la vista.
  static const List<int> _palette = [
    0xFF1A1A1A, // negro tinta
    0xFF2563EB, // azul
    0xFFDC2626, // rojo
    0xFF16A34A, // verde
    0xFFEA580C, // naranja
    0xFF9333EA, // morado
  ];

  static const List<double> _widths = [1.5, 3.0, 6.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inkCanvasProvider);
    final notifier = ref.read(inkCanvasProvider.notifier);
    final tool = state.tool;

    return Card(
      elevation: 6,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        // `Wrap` en lugar de `Row`: en una ventana estrecha o en el móvil en
        // vertical, los controles pasan a una segunda línea en vez de
        // desbordarse y provocar el aviso amarillo de overflow.
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            _ToolButton(
              icon: Icons.edit,
              tooltip: 'Bolígrafo',
              selected: tool.type == ToolType.pen,
              onPressed: () => notifier.setToolType(ToolType.pen),
            ),
            _ToolButton(
              icon: Icons.brush,
              tooltip: 'Marcador',
              selected: tool.type == ToolType.highlighter,
              onPressed: () => notifier.setToolType(ToolType.highlighter),
            ),
            _ToolButton(
              icon: Icons.auto_fix_normal,
              tooltip: 'Borrador',
              selected: tool.type == ToolType.eraser,
              onPressed: () => notifier.setToolType(ToolType.eraser),
            ),

            const _Divider(),

            for (final color in _palette)
              _ColorButton(
                colorArgb: color,
                selected: tool.colorArgb == color &&
                    tool.type != ToolType.eraser,
                onPressed: () => notifier.setColor(color),
              ),

            const _Divider(),

            for (final width in _widths)
              _WidthButton(
                width: width,
                selected: tool.width == width,
                onPressed: () => notifier.setWidth(width),
              ),

            const _Divider(),

            _ToolButton(
              icon: Icons.undo,
              tooltip: 'Deshacer',
              // Deshabilitado en lugar de oculto: un botón que aparece y
              // desaparece movería el resto de la barra y obligaría a buscar
              // los demás controles cada vez.
              onPressed: state.canUndo ? notifier.undo : null,
            ),
            _ToolButton(
              icon: Icons.redo,
              tooltip: 'Rehacer',
              onPressed: state.canRedo ? notifier.redo : null,
            ),
            _ToolButton(
              icon: Icons.delete_outline,
              tooltip: 'Vaciar el lienzo',
              onPressed: state.isEmpty
                  ? null
                  : () => _confirmClear(context, notifier),
            ),

            const _Divider(),

            _ToolButton(
              icon: state.drawWithTouch
                  ? Icons.touch_app
                  : Icons.do_not_touch_outlined,
              tooltip: state.drawWithTouch
                  ? 'El dedo dibuja: tócalo para que solo dibuje el lápiz'
                  : 'Solo dibuja el lápiz: tócalo para dibujar con el dedo',
              selected: state.drawWithTouch,
              onPressed: () => notifier.setDrawWithTouch(!state.drawWithTouch),
            ),
            _ToolButton(
              icon: Icons.zoom_out_map,
              tooltip: 'Restablecer la vista',
              onPressed: ref.read(canvasTransformProvider).reset,
            ),
          ],
        ),
      ),
    );
  }

  /// Vaciar el lienzo se puede deshacer, pero aun así se confirma: es la única
  /// acción que borra el trabajo entero de un toque, y un roce accidental
  /// asusta aunque tenga arreglo.
  Future<void> _confirmClear(
    BuildContext context,
    InkCanvasNotifier notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Vaciar el lienzo?'),
        content: const Text('Podrás recuperarlo con deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) notifier.clear();
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      style: IconButton.styleFrom(
        backgroundColor: selected ? scheme.secondaryContainer : null,
        foregroundColor: selected ? scheme.onSecondaryContainer : null,
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.colorArgb,
    required this.selected,
    required this.onPressed,
  });

  final int colorArgb;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = Color(colorArgb);
    return Tooltip(
      message: 'Color de tinta',
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              // La selección se marca con un anillo exterior y no con un borde
              // encima: un borde taparía parte del color, que es justo lo que
              // hay que poder comparar de un vistazo.
              border: selected
                  ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3)
                  : Border.all(color: Colors.black12, width: 1),
            ),
          ),
        ),
      ),
    );
  }
}

class _WidthButton extends StatelessWidget {
  const _WidthButton({
    required this.width,
    required this.selected,
    required this.onPressed,
  });

  final double width;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Grosor',
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? scheme.secondaryContainer : null,
          ),
          child: Center(
            // Un punto del tamaño real en vez de un número: el grosor es una
            // cualidad visual, y enseñarlo se entiende antes que leer "3.0".
            child: Container(
              width: width * 2.5,
              height: width * 2.5,
              decoration: BoxDecoration(
                color: scheme.onSurface,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(context).dividerColor,
    );
  }
}
