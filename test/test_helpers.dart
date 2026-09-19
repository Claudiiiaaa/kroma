import 'package:kroma/models/stroke.dart';
import 'package:kroma/models/stroke_point.dart';
import 'package:kroma/models/tool.dart';

int _counter = 0;

/// Crea un trazo a partir de coordenadas sueltas, para no repetir el mismo
/// andamiaje en cada test.
///
/// La presión y el tiempo se rellenan con valores fijos porque ninguna de las
/// dos cosas influye en lo que aquí se comprueba: límites, detección de toque y
/// serialización.
Stroke strokeFrom(
  List<(double, double)> coords, {
  String? id,
  double width = 3.0,
  ToolType tool = ToolType.pen,
  int colorArgb = 0xFF000000,
}) {
  return Stroke.fromPoints(
    id: id ?? 'trazo-${_counter++}',
    points: [
      for (var i = 0; i < coords.length; i++)
        StrokePoint(
          x: coords[i].$1,
          y: coords[i].$2,
          pressure: 0.5,
          tMs: i * 16,
        ),
    ],
    tool: tool,
    colorArgb: colorArgb,
    baseWidth: width,
    simulatePressure: false,
  );
}
