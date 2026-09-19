import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kroma/models/stroke.dart';
import 'package:kroma/models/tool.dart';
import 'package:kroma/providers/canvas_transform_controller.dart';
import 'package:kroma/models/ink_canvas_state.dart';
import 'package:kroma/models/ink_command.dart';
import 'package:kroma/providers/live_stroke_controller.dart';

/// El estado del lienzo: trazos confirmados, herramienta activa e historial.
final inkCanvasProvider =
    NotifierProvider<InkCanvasNotifier, InkCanvasState>(InkCanvasNotifier.new);

/// El trazo que se dibuja en este momento.
///
/// Es un `Provider` a secas y no un `NotifierProvider` porque su contenido no
/// es estado observado por Riverpod: es un objeto de larga vida que la capa de
/// pintado escucha por su cuenta. Riverpod aquí solo hace de inyector de
/// dependencias, que es precisamente para lo que mejor sirve.
final liveStrokeProvider = Provider<LiveStrokeController>((ref) {
  final controller = LiveStrokeController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// El desplazamiento y el zoom del lienzo.
final canvasTransformProvider = Provider<CanvasTransformController>((ref) {
  final controller = CanvasTransformController();
  ref.onDispose(controller.dispose);
  return controller;
});

class InkCanvasNotifier extends Notifier<InkCanvasState> {
  final UndoStack _undoStack = UndoStack();

  /// Trazos que el borrador ha ido quitando durante el arrastre actual.
  ///
  /// Se acumulan aquí en vez de crear un comando por cada trazo borrado,
  /// porque el usuario espera que un solo Ctrl+Z deshaga la pasada completa
  /// del borrador, no que haya que pulsarlo seis veces si borró seis trazos.
  final List<({int index, Stroke stroke})> _pendingErase = [];

  /// Identificadores de los trazos que el servidor ya tiene guardados.
  ///
  /// Es la referencia contra la que se calcula qué hay que sincronizar.
  Set<String> _serverStrokeIds = {};

  @override
  InkCanvasState build() => InkCanvasState.initial;

  // --- Sincronización -------------------------------------------------------

  /// Carga el lienzo de una tarjeta recién abierta.
  void loadStrokes(List<Stroke> strokes) {
    // El historial se vacía: deshacer no debe poder saltar de una tarjeta a la
    // anterior, porque el usuario vería desaparecer trazos que no ha dibujado
    // en esta pantalla.
    _undoStack.clear();
    _pendingErase.clear();
    _serverStrokeIds = {for (final s in strokes) s.id};

    state = state.copyWith(strokes: strokes, canUndo: false, canRedo: false);
  }

  /// Qué habría que enviar al servidor para que quede igual que la pantalla.
  ///
  /// Se calcula comparando el estado actual con lo que el servidor tiene, en
  /// lugar de ir apuntando cada operación según ocurre. La diferencia importa:
  /// llevar un registro de operaciones se rompe con el deshacer —un trazo
  /// dibujado y luego deshecho se subiría igualmente, y un trazo borrado y
  /// recuperado se borraría del servidor—. Comparando estados, el resultado es
  /// siempre correcto independientemente de cuántas veces se deshaga o rehaga.
  ({List<Stroke> added, List<String> deleted}) get pendingChanges {
    final current = state.strokes;
    final currentIds = {for (final s in current) s.id};

    return (
      added: [
        for (final s in current)
          if (!_serverStrokeIds.contains(s.id)) s,
      ],
      deleted: [
        for (final id in _serverStrokeIds)
          if (!currentIds.contains(id)) id,
      ],
    );
  }

  bool get hasPendingChanges {
    final changes = pendingChanges;
    return changes.added.isNotEmpty || changes.deleted.isNotEmpty;
  }

  /// Da por guardado el estado actual.
  ///
  /// Se llama **después** de que el servidor confirme. Si se llamara antes y la
  /// petición fallara, los cambios se darían por subidos y se perderían.
  void markSynced() {
    _serverStrokeIds = {for (final s in state.strokes) s.id};
  }

  /// Deja el lienzo vacío al salir de una tarjeta.
  void reset() {
    _undoStack.clear();
    _pendingErase.clear();
    _serverStrokeIds = {};
    state = state.copyWith(strokes: const [], canUndo: false, canRedo: false);
  }

  // --- Dibujo ---------------------------------------------------------------

  /// Registra un trazo terminado y lo apunta en el historial.
  void commitStroke(Stroke stroke) {
    _run(AddStrokeCommand(stroke));
  }

  // --- Borrado --------------------------------------------------------------

  /// Comienza una pasada del borrador.
  void beginErase() {
    _pendingErase.clear();
  }

  /// Borra los trazos que pasen a menos de [radius] del punto dado.
  ///
  /// Las coordenadas y el radio van en espacio del documento, así que quien
  /// llama debe haber dividido ya el radio en píxeles por el zoom: de lo
  /// contrario el borrador sería enorme con el lienzo alejado y minúsculo con
  /// el lienzo ampliado.
  void eraseAt({required double x, required double y, required double radius}) {
    final current = state.strokes;
    final survivors = <Stroke>[];
    var erasedAny = false;

    for (var i = 0; i < current.length; i++) {
      final stroke = current[i];
      if (stroke.hitTest(x, y, radius)) {
        // El índice se guarda respecto a la lista actual, que ya puede haber
        // encogido en este mismo arrastre. Por eso el comando deshace en orden
        // inverso; ahí está explicado en detalle.
        _pendingErase.add((index: survivors.length, stroke: stroke));
        erasedAny = true;
      } else {
        survivors.add(stroke);
      }
    }

    if (!erasedAny) return;
    state = state.copyWith(strokes: survivors);
  }

  /// Cierra la pasada del borrador y la registra como una sola acción.
  void endErase() {
    if (_pendingErase.isEmpty) return;

    // El comando se apunta en el historial sin volver a aplicarlo: el borrado
    // ya se fue reflejando en pantalla durante el arrastre, que es lo que le da
    // al borrador su sensación de respuesta inmediata.
    _undoStack.push(EraseStrokesCommand(List.of(_pendingErase)));
    _pendingErase.clear();
    _syncHistoryFlags();
  }

  /// Vacía el lienzo entero, de forma reversible.
  void clear() {
    if (state.strokes.isEmpty) return;
    _run(ClearCanvasCommand(List.of(state.strokes)));
  }

  // --- Historial ------------------------------------------------------------

  void undo() {
    final command = _undoStack.popUndo();
    if (command == null) return;
    state = state.copyWith(strokes: command.revert(state.strokes));
    _syncHistoryFlags();
  }

  void redo() {
    final command = _undoStack.popRedo();
    if (command == null) return;
    state = state.copyWith(strokes: command.apply(state.strokes));
    _syncHistoryFlags();
  }

  // --- Herramientas ---------------------------------------------------------

  void setToolType(ToolType type) {
    if (state.tool.type == type) return;
    state = state.copyWith(tool: state.tool.copyWith(type: type));
  }

  void setColor(int colorArgb) {
    // Elegir un color implica querer escribir, no borrar: el borrador no tiene
    // color, así que quedarse en él tras tocar la paleta sería desconcertante.
    final tool = state.tool.type == ToolType.eraser
        ? state.tool.copyWith(colorArgb: colorArgb, type: ToolType.pen)
        : state.tool.copyWith(colorArgb: colorArgb);
    state = state.copyWith(tool: tool);
  }

  void setWidth(double width) {
    state = state.copyWith(tool: state.tool.copyWith(width: width));
  }

  void setDrawWithTouch(bool enabled) {
    if (state.drawWithTouch == enabled) return;
    state = state.copyWith(drawWithTouch: enabled);
  }

  // --- Interno --------------------------------------------------------------

  /// Aplica un comando y lo apunta en el historial.
  void _run(InkCommand command) {
    state = state.copyWith(strokes: command.apply(state.strokes));
    _undoStack.push(command);
    _syncHistoryFlags();
  }

  /// Vuelca en el estado si hay algo que deshacer o rehacer.
  ///
  /// Las pilas viven fuera del estado inmutable porque son detalle interno,
  /// pero los botones de la barra necesitan saber si activarse, así que se
  /// copian estos dos booleanos.
  void _syncHistoryFlags() {
    state = state.copyWith(
      canUndo: _undoStack.canUndo,
      canRedo: _undoStack.canRedo,
    );
  }
}
