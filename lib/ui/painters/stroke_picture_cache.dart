import 'dart:ui' as ui;

import 'package:kroma/models/stroke.dart';
import 'package:kroma/ui/painters/stroke_geometry.dart';

/// Guarda la geometría ya calculada de los trazos confirmados.
///
/// Resuelve dos problemas de rendimiento distintos:
///
/// 1. **Geometría repetida.** Calcular el contorno de un trazo con
///    `perfect_freehand` no es gratis. Como un trazo terminado no cambia
///    jamás, su `Path` se calcula una vez y se guarda indexado por id. Sin
///    esta caché, añadir el trazo número 300 recalcularía los 299 anteriores,
///    y el coste total crecería al cuadrado: la app iría cada vez más lenta
///    cuanto más hubiera escrito el usuario.
///
/// 2. **Repintado en desplazamiento y zoom.** Los trazos se graban en un
///    [ui.Picture] en coordenadas del documento. Al mover o ampliar el lienzo
///    no hay que volver a dibujar nada: basta con reproducir esa grabación bajo
///    otra transformación. Y como un `Picture` guarda las órdenes de dibujo y
///    no píxeles, el resultado sigue siendo nítido a cualquier ampliación.
class StrokePictureCache {
  final Map<String, ui.Path> _paths = {};

  ui.Picture? _picture;
  List<Stroke>? _recordedFrom;

  /// Devuelve la grabación de [strokes], regenerándola solo si hace falta.
  ui.Picture pictureFor(List<Stroke> strokes) {
    // `identical` y no `==`: comparar dos listas de 300 trazos elemento a
    // elemento en cada fotograma costaría más que lo que ahorra. Funciona
    // porque el estado es inmutable, así que cualquier cambio real produce
    // forzosamente una lista nueva, y una lista que no ha cambiado es
    // literalmente el mismo objeto.
    final cached = _picture;
    if (cached != null && identical(_recordedFrom, strokes)) {
      return cached;
    }

    cached?.dispose();
    _picture = _record(strokes);
    _recordedFrom = strokes;
    return _picture!;
  }

  ui.Picture _record(List<Stroke> strokes) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    for (final stroke in strokes) {
      canvas.drawPath(_pathFor(stroke), _paintFor(stroke));
    }

    _evictRemoved(strokes);
    return recorder.endRecording();
  }

  ui.Path _pathFor(Stroke stroke) {
    return _paths.putIfAbsent(
      stroke.id,
      () => StrokeGeometry.buildPath(
        points: stroke.points,
        tool: stroke.tool,
        baseWidth: stroke.baseWidth,
        // El propio trazo recuerda cómo debe dibujarse, así que se ve igual
        // ahora que al reabrir la nota dentro de un mes.
        simulatePressure: stroke.simulatePressure,
        isComplete: true,
      ),
    );
  }

  ui.Paint _paintFor(Stroke stroke) {
    return StrokeGeometry.buildPaint(
      tool: stroke.tool,
      colorArgb: stroke.colorArgb,
    );
  }

  /// Olvida la geometría de los trazos que ya no están en el lienzo.
  ///
  /// Sin esto, borrar y redibujar durante una sesión larga iría acumulando en
  /// memoria el contorno de cada trazo que ha existido alguna vez. Se hace tras
  /// grabar y no al borrar porque un trazo borrado puede volver con un Ctrl+Z,
  /// y así su geometría sigue disponible mientras siga en pantalla.
  void _evictRemoved(List<Stroke> strokes) {
    if (_paths.length <= strokes.length) return;
    final alive = {for (final s in strokes) s.id};
    _paths.removeWhere((id, _) => !alive.contains(id));
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
    _recordedFrom = null;
    _paths.clear();
  }
}
