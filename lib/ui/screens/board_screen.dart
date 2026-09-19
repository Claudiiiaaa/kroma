import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kroma/services/api_exception.dart';
import 'package:kroma/providers/auth_provider.dart';
import 'package:kroma/models/board_models.dart';
import 'package:kroma/providers/board_provider.dart';
import 'package:kroma/ui/screens/card_canvas_screen.dart';
import 'package:kroma/ui/widgets/text_prompt_dialog.dart';

/// El tablero: columnas con tarjetas que se arrastran entre ellas.
class BoardScreen extends ConsumerWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(boardControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(boardAsync.value?.title ?? 'Tablero'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: () =>
                ref.read(boardControllerProvider.notifier).refresh(),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                ref.read(authControllerProvider.notifier).signOut();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Cerrar sesión'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: boardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          message: error is ApiException
              ? error.message
              : 'No se ha podido cargar el tablero.',
          onRetry: () => ref.invalidate(boardControllerProvider),
        ),
        data: (board) => _BoardColumns(board: board),
      ),
    );
  }
}

class _BoardColumns extends ConsumerWidget {
  const _BoardColumns({required this.board});

  final BoardDetail board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      // Las columnas se desplazan en horizontal, como en Notion o Trello, en
      // lugar de apilarse: así se ve de un vistazo en qué estado está todo.
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      itemCount: board.columns.length,
      itemBuilder: (context, index) =>
          _ColumnView(column: board.columns[index]),
    );
  }
}

class _ColumnView extends ConsumerWidget {
  const _ColumnView({required this.column});

  final BoardColumn column;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    column.title,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${column.cards.length}',
                      style: theme.textTheme.labelSmall),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              // Una entrada más que tarjetas: la última es la zona para soltar
              // al final de la columna, que si no sería inalcanzable.
              itemCount: column.cards.length + 1,
              itemBuilder: (context, index) {
                if (index == column.cards.length) {
                  return _DropZone(
                    columnId: column.id,
                    index: index,
                    // Alta para que sea fácil soltar en una columna vacía.
                    minHeight: column.cards.isEmpty ? 120 : 48,
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DropZone(columnId: column.id, index: index),
                    _CardTile(card: column.cards[index]),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Añadir tarjeta'),
              onPressed: () => _showAddCardDialog(context, ref, column.id),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddCardDialog(
      BuildContext context, WidgetRef ref, String columnId) async {
    final messenger = ScaffoldMessenger.of(context);

    final title = await promptForText(
      context,
      title: 'Nueva tarjeta',
      label: 'Título',
      confirmLabel: 'Crear',
    );

    if (title == null || title.isEmpty) return;

    try {
      await ref
          .read(boardControllerProvider.notifier)
          .addCard(columnId: columnId, title: title);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// Una tarjeta arrastrable.
class _CardTile extends ConsumerWidget {
  const _CardTile({required this.card});

  final NoteCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final tile = Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: Text(card.title),
        subtitle: card.hasInk
            // Indicador de que la tarjeta lleva notas a mano. Se sabe por el
            // recuento que viene con el tablero, sin descargar ni un trazo.
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.gesture, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text('${card.strokeCount} trazos',
                      style: theme.textTheme.labelSmall),
                ],
              )
            : null,
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _onAction(context, ref, value),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('Renombrar')),
            PopupMenuItem(value: 'delete', child: Text('Borrar')),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => CardCanvasScreen(card: card),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      // Mantener pulsado para arrastrar, y no arrastrar directamente: en el
      // móvil, el gesto de arrastre es el mismo que el de desplazar la lista, y
      // sin la pulsación larga no se podría hacer scroll por la columna.
      child: LongPressDraggable<NoteCard>(
        data: card,
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 280, child: tile),
        ),
        // El hueco original queda atenuado para no perder de vista de dónde
        // salió la tarjeta mientras se mueve.
        childWhenDragging: Opacity(opacity: 0.3, child: tile),
        child: tile,
      ),
    );
  }

  Future<void> _onAction(
      BuildContext context, WidgetRef ref, String action) async {
    final notifier = ref.read(boardControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Borrar la tarjeta?'),
          content: Text(
            card.hasInk
                // Se avisa de que se pierde la tinta: borrar una tarjeta con
                // notas a mano destruye trabajo que no está en ningún otro sitio.
                ? 'Se perderán también sus ${card.strokeCount} trazos. '
                    'Esto no se puede deshacer.'
                : 'Esto no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Borrar'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      try {
        await notifier.deleteCard(cardId: card.id, columnId: card.columnId);
      } on ApiException catch (error) {
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }

    if (action == 'rename') {
      final title = await promptForText(
        context,
        title: 'Renombrar tarjeta',
        label: 'Título',
        confirmLabel: 'Guardar',
        initialValue: card.title,
      );

      if (title == null || title.isEmpty || title == card.title) return;

      try {
        await notifier.renameCard(
          cardId: card.id,
          columnId: card.columnId,
          title: title,
        );
      } on ApiException catch (error) {
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

/// Franja entre tarjetas donde se puede soltar la que se arrastra.
///
/// Hay una antes de cada tarjeta y otra al final de la columna, y cada una
/// conoce el índice que le corresponde. Así se decide el lugar exacto donde se
/// inserta, en vez de dejarla siempre al final como haría una única zona por
/// columna.
class _DropZone extends ConsumerStatefulWidget {
  const _DropZone({
    required this.columnId,
    required this.index,
    this.minHeight = 8,
  });

  final String columnId;
  final int index;
  final double minHeight;

  @override
  ConsumerState<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends ConsumerState<_DropZone> {
  @override
  Widget build(BuildContext context) {
    return DragTarget<NoteCard>(
      onAcceptWithDetails: (details) async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await ref.read(boardControllerProvider.notifier).moveCard(
                cardId: details.data.id,
                targetColumnId: widget.columnId,
                targetIndex: widget.index,
              );
        } on ApiException catch (error) {
          messenger.showSnackBar(SnackBar(content: Text(error.message)));
        }
      },
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          // La franja crece al pasar una tarjeta por encima: enseña el hueco
          // donde va a caer antes de soltarla.
          height: active ? 72 : widget.minHeight,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
