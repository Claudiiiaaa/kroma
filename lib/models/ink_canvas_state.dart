import 'package:flutter/foundation.dart';

import 'package:kroma/models/stroke.dart';
import 'package:kroma/models/tool.dart';

/// Estado del lienzo que cambia con poca frecuencia.
///
/// Aquí está todo lo que se actualiza unas pocas veces por minuto: los trazos
/// ya terminados, la herramienta elegida y si hay algo que deshacer. El trazo
/// en curso y el zoom **no** están aquí a propósito, porque cambian cien veces
/// por segundo y tienen sus propios controladores.
@immutable
class InkCanvasState {
  const InkCanvasState({
    required this.strokes,
    required this.tool,
    required this.canUndo,
    required this.canRedo,
    required this.drawWithTouch,
  });

  /// Los trazos, en orden de pintado: el primero es el de más abajo.
  final List<Stroke> strokes;

  final ToolSettings tool;

  final bool canUndo;
  final bool canRedo;

  /// Si el dedo y el ratón pueden dibujar, además del lápiz.
  ///
  /// Con esto desactivado, el dedo solo desplaza y amplía, y solo el lápiz
  /// dibuja: es el modelo de GoodNotes y resuelve el apoyo de la palma sin
  /// detectar nada. Pero tú vas a desarrollar en Windows con ratón y tu hermana
  /// puede abrirlo en el navegador, así que tiene que poder activarse.
  final bool drawWithTouch;

  bool get isEmpty => strokes.isEmpty;

  static const InkCanvasState initial = InkCanvasState(
    strokes: [],
    tool: ToolSettings.initial,
    canUndo: false,
    canRedo: false,
    // Arranca activado porque la primera ejecución será en escritorio o en web,
    // donde no hay lápiz. En una tablet con lápiz conviene apagarlo.
    drawWithTouch: true,
  );

  InkCanvasState copyWith({
    List<Stroke>? strokes,
    ToolSettings? tool,
    bool? canUndo,
    bool? canRedo,
    bool? drawWithTouch,
  }) {
    return InkCanvasState(
      strokes: strokes ?? this.strokes,
      tool: tool ?? this.tool,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      drawWithTouch: drawWithTouch ?? this.drawWithTouch,
    );
  }
}
