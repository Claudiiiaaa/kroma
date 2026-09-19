import 'package:uuid/uuid.dart';

import 'package:kroma/models/stroke.dart';
import 'package:kroma/models/stroke_point.dart';
import 'package:kroma/models/tool.dart';

/// Acumula los puntos del trazo que se está dibujando ahora mismo.
///
/// Es la contrapartida mutable de [Stroke], y existe por rendimiento. Mientras
/// el lápiz se mueve llegan más de cien eventos por segundo; si cada uno
/// creara una lista nueva de puntos, generaríamos tal cantidad de basura que el
/// recolector provocaría tirones visibles justo mientras se escribe. Aquí se
/// muta una sola lista, y al levantar el lápiz se congela en un [Stroke]
/// inmutable que ya nadie volverá a tocar.
class StrokeBuilder {
  StrokeBuilder({
    required this.tool,
    required this.colorArgb,
    required this.baseWidth,
    required this.hasRealPressure,
    DateTime? startedAt,
  }) : id = _uuid.v7(),
       _startedAt = startedAt ?? DateTime.now();

  /// UUID v7 en lugar de v4: los dos son únicos, pero el v7 codifica el
  /// instante de creación en sus bits altos, así que ordena cronológicamente.
  /// Cuando estos trazos lleguen a un índice de Postgres, los v7 se insertarán
  /// siempre al final del árbol B en vez de dispersarse por él como harían los
  /// v4 aleatorios. Elegirlo bien ahora es gratis; cambiarlo después, no.
  static const _uuid = Uuid();

  final String id;
  final ToolType tool;
  final int colorArgb;
  final double baseWidth;

  /// Si el dispositivo que dibuja este trazo mide presión de verdad.
  ///
  /// Lo decide la capa de captura mirando el tipo de puntero: un lápiz sí, un
  /// ratón o un dedo no. Viaja hasta el trazo terminado porque determina cómo
  /// debe dibujarse para siempre, no solo mientras se traza.
  final bool hasRealPressure;

  final DateTime _startedAt;
  final List<StrokePoint> _points = [];

  /// Vista de solo lectura para que quien pinte no pueda modificar la lista.
  /// No es una copia: pintar se hace en cada fotograma y copiar aquí sería
  /// exactamente la basura que este builder existe para evitar.
  List<StrokePoint> get points => List.unmodifiable(_points);

  /// Acceso directo sin envoltorio, solo para el pintado en caliente.
  List<StrokePoint> get pointsUnsafe => _points;

  bool get isEmpty => _points.isEmpty;
  int get length => _points.length;

  /// Añade un punto si aporta información nueva.
  ///
  /// [minDistance] se expresa en coordenadas del documento y debe venir ya
  /// dividido por el zoom actual: con el lienzo alejado, un mismo gesto de la
  /// mano recorre más distancia de documento, y un umbral fijo descartaría
  /// detalle real del trazo.
  ///
  /// Devuelve `true` si el punto se añadió, para que quien llama sepa si hace
  /// falta repintar.
  bool addPoint({
    required double x,
    required double y,
    required double pressure,
    double minDistance = 0.0,
  }) {
    if (_points.isNotEmpty && minDistance > 0) {
      final last = _points.last;
      final dx = x - last.x;
      final dy = y - last.y;
      // Se compara con el cuadrado para ahorrarse la raíz cuadrada.
      if (dx * dx + dy * dy < minDistance * minDistance) return false;
    }

    _points.add(
      StrokePoint(
        x: x,
        y: y,
        // Algunos dispositivos entregan presión 0 en el primer evento del
        // trazo, antes de que el sensor se estabilice. Dejarla a cero haría
        // que el trazo empezara con grosor nulo y parpadeara al aparecer.
        pressure: pressure <= 0 ? StrokePoint.defaultPressure : pressure,
        tMs: DateTime.now().difference(_startedAt).inMilliseconds,
      ),
    );
    return true;
  }

  /// Congela el trazo. Devuelve `null` si no hay nada que guardar, cosa que
  /// ocurre si el usuario apoyó y levantó el lápiz sin llegar a moverlo y el
  /// evento inicial se descartó.
  Stroke? build() {
    if (_points.isEmpty) return null;

    // Un toque seco produce un solo punto, y un trazo de un punto no tiene
    // segmentos que dibujar. Se duplica ligeramente desplazado para que salga
    // el punto redondo que el usuario espera al dar un toque.
    if (_points.length == 1) {
      final p = _points.first;
      _points.add(p.copyWith(x: p.x + 0.01, y: p.y + 0.01));
    }

    return Stroke.fromPoints(
      id: id,
      points: _points,
      tool: tool,
      colorArgb: colorArgb,
      baseWidth: baseWidth,
      simulatePressure: !hasRealPressure,
    );
  }
}
