import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kroma/services/api_exception.dart';
import 'package:kroma/providers/ink_provider.dart';
import 'package:kroma/ui/widgets/ink_canvas.dart';
import 'package:kroma/ui/widgets/ink_toolbar.dart';
import 'package:kroma/services/board_service.dart';
import 'package:kroma/models/board_models.dart';
import 'package:kroma/providers/board_provider.dart';

/// El lienzo de una tarjeta: aquí se escribe a mano.
class CardCanvasScreen extends ConsumerStatefulWidget {
  const CardCanvasScreen({super.key, required this.card});

  final NoteCard card;

  @override
  ConsumerState<CardCanvasScreen> createState() => _CardCanvasScreenState();
}

class _CardCanvasScreenState extends ConsumerState<CardCanvasScreen> {
  /// Espera tras el último trazo antes de guardar.
  ///
  /// Guardar en cada trazo saturaría la red escribiendo, y guardar solo al
  /// salir arriesga perderlo todo si la app se cierra de golpe. Esperar a que
  /// la mano se detenga un par de segundos da lo mejor de ambos.
  static const Duration _saveDebounce = Duration(seconds: 2);

  Timer? _saveTimer;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Se aplaza al primer fotograma: durante `initState` el widget todavía no
    // está montado y no se puede modificar el estado de otros providers.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStrokes());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStrokes() async {
    try {
      final strokes =
          await ref.read(boardServiceProvider).getStrokes(widget.card.id);
      if (!mounted) return;
      ref.read(inkCanvasProvider.notifier).loadStrokes(strokes);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleSave() {
    // Cada trazo nuevo reinicia la cuenta atrás, así que mientras se escriba
    // seguido no se envía nada: solo cuando la mano para.
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () => _save());
  }

  Future<bool> _save() async {
    _saveTimer?.cancel();

    final notifier = ref.read(inkCanvasProvider.notifier);
    final changes = notifier.pendingChanges;

    if (changes.added.isEmpty && changes.deleted.isEmpty) return true;

    if (mounted) setState(() => _saving = true);

    try {
      await ref.read(boardServiceProvider).syncStrokes(
            cardId: widget.card.id,
            added: changes.added,
            deletedIds: changes.deleted,
          );

      // Solo después de que el servidor confirme se da por sincronizado. Al
      // revés, un fallo de red daría los trazos por guardados y se perderían.
      notifier.markSynced();

      // El tablero muestra un indicador en las tarjetas con tinta, así que hay
      // que avisarle del nuevo recuento sin tener que recargarlo entero.
      ref.read(boardControllerProvider.notifier).updateStrokeCount(
            cardId: widget.card.id,
            strokeCount: ref.read(inkCanvasProvider).strokes.length,
          );

      if (mounted) setState(() => _error = null);
      return true;
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Guarda antes de salir y avisa si no se pudo.
  Future<void> _handleClose() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final saved = await _save();

    // `_save` es asíncrono, así que entre su inicio y este punto el widget
    // puede haberse desmontado y su `context` haber dejado de ser válido.
    if (!mounted) return;

    if (!saved) {
      // Salir en silencio dejaría creer que la nota está a salvo. Se pregunta
      // antes de descartar trabajo.
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No se ha podido guardar'),
          content: const Text(
            'Los cambios de esta nota no han llegado al servidor. '
            '¿Quieres salir de todas formas y perderlos?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Seguir aquí'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Salir y perderlos'),
            ),
          ],
        ),
      );

      if (leave != true) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Se han descartado los cambios.')),
      );
    }

    ref.read(inkCanvasProvider.notifier).reset();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    // Cada vez que cambian los trazos se reinicia la cuenta atrás del guardado.
    ref.listen(inkCanvasProvider.select((s) => s.strokes), (previous, next) {
      if (previous != null && !identical(previous, next)) _scheduleSave();
    });

    return PopScope(
      // Se intercepta la salida —incluido el botón atrás de Android y el gesto
      // del borde— para guardar antes de cerrar.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleClose,
          ),
          title: Text(widget.card.title, overflow: TextOverflow.ellipsis),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.cloud_done_outlined),
                tooltip: 'Guardar ahora',
                onPressed: _save,
              ),
          ],
        ),
        body: Stack(
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              const Positioned.fill(child: InkCanvas()),

            if (!_loading)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FittedBox(child: InkToolbar()),
                    ),
                  ),
                ),
              ),

            if (_error != null)
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!)),
                        TextButton(
                          onPressed: _save,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
