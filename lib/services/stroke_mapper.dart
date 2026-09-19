import 'package:kroma/models/stroke.dart';
import 'package:kroma/models/stroke_point.dart';
import 'package:kroma/models/tool.dart';

/// Traduce los trazos entre el modelo de la app y el formato de la API.
///
/// Los dos guardan lo mismo, pero con distinta forma: en la app cada punto es
/// un objeto `StrokePoint`, mientras que por la red viajan aplanados en una
/// sola lista de números, de cuatro en cuatro. Ese aplanado ahorra mucho:
/// repetir las claves «x», «y», «pressure» y «tMs» en cada uno de los cientos
/// de puntos de un trazo multiplicaría por varias veces el tamaño de cada
/// petición, y esto se envía desde el móvil.
class StrokeMapper {
  const StrokeMapper._();

  /// Valores que ocupa cada punto. Debe coincidir con el backend.
  static const int valuesPerPoint = 4;

  static Map<String, dynamic> toJson(Stroke stroke) => {
        'id': stroke.id,
        'tool': stroke.tool.name,
        'colorArgb': stroke.colorArgb,
        'baseWidth': stroke.baseWidth,
        'simulatePressure': stroke.simulatePressure,
        'points': [
          for (final p in stroke.points) ...[
            p.x,
            p.y,
            p.pressure,
            p.tMs.toDouble(),
          ],
        ],
      };

  static Stroke fromJson(Map<String, dynamic> json) {
    final flat = (json['points'] as List).cast<num>();
    final points = <StrokePoint>[];

    // El paso de cuatro en cuatro, y la condición mirando al último de los
    // cuatro, evitan leer fuera de la lista si llegara un número de valores que
    // no fuese múltiplo de cuatro. El servidor lo valida, pero un cliente no se
    // fía de que el otro lado haya hecho los deberes.
    for (var i = 0; i + valuesPerPoint - 1 < flat.length; i += valuesPerPoint) {
      points.add(StrokePoint(
        x: flat[i].toDouble(),
        y: flat[i + 1].toDouble(),
        pressure: flat[i + 2].toDouble(),
        tMs: flat[i + 3].toInt(),
      ));
    }

    return Stroke.fromPoints(
      id: json['id'] as String,
      points: points,
      tool: ToolType.fromName(json['tool'] as String),
      colorArgb: (json['colorArgb'] as num).toInt(),
      baseWidth: (json['baseWidth'] as num).toDouble(),
      simulatePressure: json['simulatePressure'] as bool? ?? false,
    );
  }
}
