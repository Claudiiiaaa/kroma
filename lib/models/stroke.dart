import 'dart:math' as math;

import 'package:kroma/models/stroke_point.dart';
import 'package:kroma/models/tool.dart';

/// Un trazo terminado: el usuario ya levantó el lápiz.
///
/// Es inmutable por completo. Una vez cerrado, un trazo no se edita nunca:
/// borrar significa quitarlo de la lista, no vaciarlo. Eso simplifica
/// muchísimo el deshacer/rehacer y, más adelante, la sincronización, porque un
/// trazo que nunca cambia no puede entrar en conflicto con el servidor.
class Stroke {
  const Stroke({
    required this.id,
    required this.points,
    required this.tool,
    required this.colorArgb,
    required this.baseWidth,
    required this.simulatePressure,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  /// UUID generado en el cliente, no un autoincremental del servidor.
  ///
  /// Es deliberado: la app funciona sin conexión, así que necesita poder crear
  /// trazos con identidad propia sin preguntarle a nadie. Cuando llegue la
  /// sincronización, el servidor aceptará este id tal cual y no habrá que
  /// reconciliar identificadores provisionales.
  final String id;

  final List<StrokePoint> points;
  final ToolType tool;
  final int colorArgb;
  final double baseWidth;

  /// Si el grosor debe deducirse de la velocidad en vez de la presión guardada.
  ///
  /// Se decide al capturar el trazo: vale `true` cuando lo dibujó un ratón o un
  /// dedo, porque esos no miden presión. Guardarlo en el trazo es lo que hace
  /// que el dibujo sea **determinista**: sin este dato, una nota hecha con
  /// ratón se vería con grosor variable mientras se dibuja y plana al volver a
  /// abrirla, porque la velocidad del gesto ya no existiría en ninguna parte.
  final bool simulatePressure;

  /// Rectángulo que envuelve al trazo, ya inflado por el grosor.
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  /// Construye un trazo calculando sus límites en una sola pasada.
  factory Stroke.fromPoints({
    required String id,
    required List<StrokePoint> points,
    required ToolType tool,
    required int colorArgb,
    required double baseWidth,
    required bool simulatePressure,
  }) {
    if (points.isEmpty) {
      throw ArgumentError('Un trazo necesita al menos un punto');
    }

    var minX = points.first.x;
    var minY = points.first.y;
    var maxX = minX;
    var maxY = minY;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }

    // El trazo dibujado sobresale medio grosor de sus puntos matemáticos. Sin
    // este margen, el borrador fallaría al tocar justo el borde visible.
    final margin = baseWidth;

    return Stroke(
      id: id,
      points: List.unmodifiable(points),
      tool: tool,
      colorArgb: colorArgb,
      baseWidth: baseWidth,
      simulatePressure: simulatePressure,
      minX: minX - margin,
      minY: minY - margin,
      maxX: maxX + margin,
      maxY: maxY + margin,
    );
  }

  /// Descarte rápido: ¿puede este trazo estar cerca del punto dado?
  ///
  /// Cuatro comparaciones que eliminan la inmensa mayoría de los trazos antes
  /// de gastar tiempo en [hitTest], que es mucho más caro.
  bool couldContain(double px, double py, double radius) {
    return px >= minX - radius &&
        px <= maxX + radius &&
        py >= minY - radius &&
        py <= maxY + radius;
  }

  /// ¿Pasa el trazo a menos de [radius] del punto dado?
  ///
  /// Recorre los segmentos midiendo la distancia del punto a cada uno. Mide
  /// contra el *segmento* y no contra sus extremos porque, con el lápiz rápido,
  /// dos puntos consecutivos pueden quedar muy separados: si solo comprobáramos
  /// los vértices, el borrador atravesaría el trazo sin borrarlo.
  bool hitTest(double px, double py, double radius) {
    if (!couldContain(px, py, radius)) return false;

    // Margen real: el radio del borrador más el medio grosor del trazo.
    final threshold = radius + baseWidth / 2;
    final thresholdSq = threshold * threshold;

    if (points.length == 1) {
      return _distanceSquared(px, py, points[0].x, points[0].y) <= thresholdSq;
    }

    for (var i = 0; i < points.length - 1; i++) {
      final d = _pointToSegmentDistanceSquared(
        px,
        py,
        points[i].x,
        points[i].y,
        points[i + 1].x,
        points[i + 1].y,
      );
      if (d <= thresholdSq) return true;
    }
    return false;
  }

  /// ¿Se solapa este trazo con el rectángulo dado?
  ///
  /// Se usará para repintar solo la zona afectada y, más adelante, para el
  /// lazo de selección.
  bool intersectsRect(double left, double top, double right, double bottom) {
    return !(maxX < left || minX > right || maxY < top || minY > bottom);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tool': tool.name,
    'color': colorArgb,
    'width': baseWidth,
    'sim': simulatePressure,
    'points': points.map((p) => p.toJson()).toList(),
  };

  factory Stroke.fromJson(Map<String, dynamic> json) {
    final points = (json['points'] as List)
        .map((p) => StrokePoint.fromJson(p as List))
        .toList();

    // Los límites se recalculan en lugar de guardarse: son datos derivados, y
    // guardar datos derivados es pedir que algún día dejen de coincidir con la
    // realidad. Además ahorra espacio en la base de datos.
    return Stroke.fromPoints(
      id: json['id'] as String,
      points: points,
      tool: ToolType.fromName(json['tool'] as String),
      colorArgb: (json['color'] as num).toInt(),
      baseWidth: (json['width'] as num).toDouble(),
      // Con valor por defecto para que una nota guardada por una versión
      // anterior del formato se siga leyendo en lugar de reventar.
      simulatePressure: json['sim'] as bool? ?? false,
    );
  }

  @override
  String toString() => 'Stroke($id, ${tool.name}, ${points.length} puntos)';
}

double _distanceSquared(double ax, double ay, double bx, double by) {
  final dx = ax - bx;
  final dy = ay - by;
  return dx * dx + dy * dy;
}

/// Distancia al cuadrado de un punto al segmento AB.
///
/// Devuelve el cuadrado para evitar la raíz cuadrada, que es cara y aquí
/// innecesaria: comparar `d² <= umbral²` da exactamente el mismo resultado que
/// comparar `d <= umbral`, y esta función se ejecuta miles de veces por
/// segundo mientras se arrastra el borrador.
double _pointToSegmentDistanceSquared(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final abx = bx - ax;
  final aby = by - ay;
  final lengthSq = abx * abx + aby * aby;

  // Segmento degenerado (A y B coinciden): es una distancia punto a punto.
  if (lengthSq == 0) return _distanceSquared(px, py, ax, ay);

  // Proyección de AP sobre AB, normalizada a [0, 1]. El recorte con clamp es
  // lo que mide contra el segmento y no contra la recta infinita que lo
  // contiene: sin él, un punto alineado pero lejano daría distancia cero.
  var t = ((px - ax) * abx + (py - ay) * aby) / lengthSq;
  t = math.max(0, math.min(1, t));

  final closestX = ax + t * abx;
  final closestY = ay + t * aby;
  return _distanceSquared(px, py, closestX, closestY);
}
