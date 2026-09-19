import 'package:flutter/foundation.dart';

import 'package:kroma/models/stroke_builder.dart';

/// El trazo que se está dibujando en este preciso instante.
///
/// Deliberadamente **fuera de Riverpod**. Mientras el lápiz se mueve, este
/// objeto cambia más de cien veces por segundo; si fuera estado de Riverpod,
/// cada uno de esos cambios reconstruiría widgets, y reconstruir widgets a esa
/// frecuencia es justo lo que hace que las apps de dibujo vayan a tirones.
///
/// Al ser un [ChangeNotifier], se puede pasar directamente al parámetro
/// `repaint:` de un `CustomPainter`. Entonces Flutter se salta las fases de
/// construcción y de layout por completo y va directo a pintar. Es la
/// diferencia entre repintar unos cuantos píxeles y reconstruir el árbol.
class LiveStrokeController extends ChangeNotifier {
  StrokeBuilder? _builder;

  /// El trazo en curso, o `null` si el lápiz no está apoyado.
  StrokeBuilder? get builder => _builder;

  bool get isDrawing => _builder != null;

  /// El lápiz acaba de tocar el lienzo.
  void begin(StrokeBuilder builder) {
    _builder = builder;
    notifyListeners();
  }

  /// El lápiz se ha movido. Solo notifica si el punto se aceptó, para no
  /// repintar cuando el filtro de distancia mínima descarta el movimiento.
  void extend({
    required double x,
    required double y,
    required double pressure,
    double minDistance = 0.0,
  }) {
    final builder = _builder;
    if (builder == null) return;

    final added = builder.addPoint(
      x: x,
      y: y,
      pressure: pressure,
      minDistance: minDistance,
    );
    if (added) notifyListeners();
  }

  /// El lápiz se ha levantado. Devuelve el constructor para que quien llama lo
  /// congele en un trazo definitivo, y limpia el estado vivo.
  StrokeBuilder? finish() {
    final builder = _builder;
    _builder = null;
    notifyListeners();
    return builder;
  }

  /// Descarta el trazo en curso sin guardarlo.
  ///
  /// Se usa cuando el sistema cancela el puntero: una llamada entrante, un
  /// gesto del sistema desde el borde de la pantalla, o el usuario apoyando un
  /// segundo dedo para hacer zoom a mitad de trazo.
  void cancel() {
    if (_builder == null) return;
    _builder = null;
    notifyListeners();
  }
}
