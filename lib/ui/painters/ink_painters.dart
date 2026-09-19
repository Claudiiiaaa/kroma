import 'package:flutter/widgets.dart';

import 'package:kroma/models/stroke.dart';
import 'package:kroma/providers/canvas_transform_controller.dart';
import 'package:kroma/providers/live_stroke_controller.dart';
import 'package:kroma/ui/painters/stroke_geometry.dart';
import 'package:kroma/ui/painters/stroke_picture_cache.dart';

/// Pinta los trazos ya terminados: la capa de abajo, que casi nunca cambia.
///
/// Reproduce la grabación cacheada bajo la transformación actual. Desplazar o
/// ampliar el lienzo no recalcula ninguna geometría, solo cambia la matriz.
class ConfirmedStrokesPainter extends CustomPainter {
  ConfirmedStrokesPainter({
    required this.strokes,
    required this.cache,
    required this.transform,
  }) : super(repaint: transform);

  final List<Stroke> strokes;
  final StrokePictureCache cache;
  final CanvasTransformController transform;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.transform(transform.matrix.storage);
    canvas.drawPicture(cache.pictureFor(strokes));
    canvas.restore();
  }

  @override
  bool shouldRepaint(ConfirmedStrokesPainter oldDelegate) {
    // Basta comparar identidades: el estado es inmutable, así que una lista que
    // no ha cambiado es el mismo objeto. Los cambios de la transformación no se
    // comprueban aquí porque llegan por el `repaint:` del constructor.
    return !identical(oldDelegate.strokes, strokes) ||
        !identical(oldDelegate.cache, cache);
  }
}

/// Pinta únicamente el trazo que se está dibujando: la capa de arriba.
///
/// Este es el pintor que trabaja a ritmo de lápiz. Al recibir un [Listenable]
/// en `repaint:`, cada punto nuevo provoca solo una fase de pintado: Flutter no
/// reconstruye widgets ni recalcula el layout. Esa es toda la razón de ser de
/// la separación en dos capas, y lo que permite mantener los 60 fps con
/// cientos de trazos ya en pantalla.
class LiveStrokePainter extends CustomPainter {
  LiveStrokePainter({
    required this.live,
    required this.transform,
  }) : super(repaint: Listenable.merge([live, transform]));

  final LiveStrokeController live;
  final CanvasTransformController transform;

  @override
  void paint(Canvas canvas, Size size) {
    final builder = live.builder;
    if (builder == null || builder.isEmpty) return;

    canvas.save();
    canvas.transform(transform.matrix.storage);

    final path = StrokeGeometry.buildPath(
      // Se usa la lista interna sin envolver: envolverla en cada fotograma
      // crearía justo la basura que el builder existe para evitar.
      points: builder.pointsUnsafe,
      tool: builder.tool,
      baseWidth: builder.baseWidth,
      simulatePressure: !builder.hasRealPressure,
      // El trazo sigue abierto: el algoritmo deja la punta sin rematar porque
      // todavía no sabe hacia dónde va a girar la mano.
      isComplete: false,
    );

    canvas.drawPath(
      path,
      StrokeGeometry.buildPaint(
        tool: builder.tool,
        colorArgb: builder.colorArgb,
      ),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(LiveStrokePainter oldDelegate) {
    // El repintado lo dispara el `Listenable`, no la reconstrucción del widget.
    // Solo hace falta repintar aquí si nos han cambiado los controladores.
    return !identical(oldDelegate.live, live) ||
        !identical(oldDelegate.transform, transform);
  }
}
