import 'package:kroma/models/stroke.dart';

/// Una acción reversible sobre el lienzo.
///
/// Es el patrón Command. La alternativa ingenua para deshacer es guardar una
/// copia completa del lienzo antes de cada cambio, pero con 500 trazos eso
/// significa duplicar el documento entero cada vez que se dibuja una línea. Un
/// comando guarda solo la diferencia: qué se añadió o qué se quitó.
///
/// Los métodos devuelven una lista nueva en lugar de modificar la recibida
/// porque el estado de Riverpod debe ser inmutable; si mutáramos la lista en
/// sitio, Riverpod compararía el objeto consigo mismo, no vería cambio alguno
/// y la interfaz no se refrescaría.
abstract class InkCommand {
  /// Aplica el cambio (hacer, o rehacer).
  List<Stroke> apply(List<Stroke> strokes);

  /// Deshace el cambio, dejando el lienzo exactamente como estaba.
  List<Stroke> revert(List<Stroke> strokes);
}

/// Añadir un trazo al lienzo.
class AddStrokeCommand implements InkCommand {
  const AddStrokeCommand(this.stroke);

  final Stroke stroke;

  @override
  List<Stroke> apply(List<Stroke> strokes) => [...strokes, stroke];

  @override
  List<Stroke> revert(List<Stroke> strokes) =>
      strokes.where((s) => s.id != stroke.id).toList();
}

/// Borrar uno o varios trazos de una sola pasada del borrador.
///
/// Toda la pasada es **un solo comando**, no uno por trazo. Si el usuario
/// arrastra el borrador sobre seis trazos, espera que un único Ctrl+Z los
/// devuelva todos, no tener que pulsarlo seis veces.
class EraseStrokesCommand implements InkCommand {
  const EraseStrokesCommand(this.removed);

  /// Los trazos borrados, **en el orden en que se fueron borrando**, junto con
  /// la posición que ocupaba cada uno en el momento de quitarlo.
  ///
  /// Guardar el índice es imprescindible: el orden de la lista es el orden de
  /// pintado, es decir, qué trazo queda por encima de cuál. Si al deshacer
  /// devolviéramos los trazos al final, un subrayado que estaba debajo del
  /// texto reaparecería encima, tapándolo.
  final List<({int index, Stroke stroke})> removed;

  @override
  List<Stroke> apply(List<Stroke> strokes) {
    final ids = removed.map((e) => e.stroke.id).toSet();
    return strokes.where((s) => !ids.contains(s.id)).toList();
  }

  @override
  List<Stroke> revert(List<Stroke> strokes) {
    final result = [...strokes];
    // Se reinsertan en orden **inverso** al del borrado, y el motivo es sutil.
    // Durante un arrastre del borrador, cada trazo se quita de una lista que ya
    // había encogido con los anteriores, así que cada índice solo es válido
    // respecto al estado que había justo en ese momento. Deshaciendo del último
    // al primero, cada inserción reconstruye exactamente el estado previo a esa
    // eliminación, y el índice siguiente vuelve a ser correcto.
    //
    // Con el orden ascendente fallaría: borrar C de [A,B,C,D,E] y luego E
    // produce los índices 2 y 3; reinsertando 2 y después 3 se obtendría
    // [A,B,C,E,D], con D y E intercambiados.
    for (final entry in removed.reversed) {
      final at = entry.index.clamp(0, result.length);
      result.insert(at, entry.stroke);
    }
    return result;
  }
}

/// Vaciar el lienzo por completo.
class ClearCanvasCommand implements InkCommand {
  const ClearCanvasCommand(this.previous);

  final List<Stroke> previous;

  @override
  List<Stroke> apply(List<Stroke> strokes) => const [];

  @override
  List<Stroke> revert(List<Stroke> strokes) => [...previous];
}

/// Las dos pilas del deshacer/rehacer.
///
/// Funciona como el historial de un navegador: al deshacer, el comando pasa de
/// la pila de deshacer a la de rehacer; al ejecutar una acción nueva, la pila
/// de rehacer se vacía, porque acabas de crear una rama distinta de la historia
/// y el futuro que habías descartado ya no tiene sentido.
class UndoStack {
  UndoStack({this.maxDepth = 100});

  /// Tope del historial. Sin límite, una sesión larga de dibujo acabaría
  /// reteniendo en memoria todos los trazos borrados desde que abrió la app.
  final int maxDepth;

  final List<InkCommand> _undoStack = [];
  final List<InkCommand> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Registra un comando ya aplicado.
  void push(InkCommand command) {
    _undoStack.add(command);
    _redoStack.clear();
    if (_undoStack.length > maxDepth) {
      _undoStack.removeAt(0);
    }
  }

  /// Devuelve el comando a deshacer, o `null` si no hay nada.
  InkCommand? popUndo() {
    if (_undoStack.isEmpty) return null;
    final command = _undoStack.removeLast();
    _redoStack.add(command);
    return command;
  }

  /// Devuelve el comando a rehacer, o `null` si no hay nada.
  InkCommand? popRedo() {
    if (_redoStack.isEmpty) return null;
    final command = _redoStack.removeLast();
    _undoStack.add(command);
    return command;
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
