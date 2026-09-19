import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart';

import 'package:kroma/models/stroke_point.dart' as domain;
import 'package:kroma/models/tool.dart';

/// Traduce los puntos capturados a una silueta dibujable.
///
/// Un trazo no se pinta como una línea de grosor constante: se calcula el
/// **contorno** de la mancha de tinta, un polígono cerrado más ancho donde se
/// apretó y afilado en los extremos, y se rellena. Eso es lo que hace que la
/// escritura parezca escritura y no un cable.
///
/// De ese cálculo se encarga `perfect_freehand`, el mismo algoritmo que usa
/// tldraw. Aquí solo se adaptan nuestros modelos a su entrada y su salida.
class StrokeGeometry {
  const StrokeGeometry._();

  /// Construye la silueta rellenable de un trazo.
  ///
  /// [isComplete] distingue un trazo terminado de uno en curso: mientras el
  /// lápiz sigue apoyado, el algoritmo dibuja el final ligeramente por detrás
  /// del último punto, porque todavía no sabe hacia dónde va a girar. Rematarlo
  /// antes de tiempo produce un parpadeo en la punta al seguir escribiendo.
  static Path buildPath({
    required List<domain.StrokePoint> points,
    required ToolType tool,
    required double baseWidth,
    required bool simulatePressure,
    required bool isComplete,
  }) {
    if (points.isEmpty) return Path();

    final input = [
      for (final p in points) PointVector(p.x, p.y, p.pressure),
    ];

    final outline = getStroke(
      input,
      options: StrokeOptions(
        size: baseWidth,

        // Cuánto adelgaza el trazo al aflojar la presión. El marcador lleva 0
        // porque una punta de fieltro es rígida y no responde a la presión.
        thinning: tool == ToolType.highlighter ? 0.0 : 0.5,

        // Suaviza las esquinas del contorno.
        smoothing: 0.5,

        // Cuánto se ignora el temblor de la entrada. Subirlo da trazos más
        // limpios pero con sensación de retardo, porque la línea se queda
        // detrás de la punta del lápiz. 0.4 es un término medio que no se nota.
        streamline: 0.4,

        // Si el dispositivo no mide presión (ratón, o dedo en la mayoría de
        // pantallas), se deduce de la velocidad del gesto: al escribir rápido
        // el trazo adelgaza, igual que con un bolígrafo de verdad. Sin esto, el
        // dibujo con ratón queda como una línea plana y muerta.
        simulatePressure: simulatePressure,

        isComplete: isComplete,
      ),
    );

    return _outlineToPath(outline);
  }

  /// Convierte el polígono del contorno en un [Path] con esquinas suavizadas.
  ///
  /// Unir los vértices con rectas dejaría un borde facetado visible al ampliar.
  /// En vez de eso se traza una curva cuadrática por cada vértice, usando el
  /// propio vértice como punto de control y el punto medio hacia el siguiente
  /// como destino. Es un truco clásico: la curva resultante pasa suavemente
  /// "rozando" cada esquina en lugar de pincharla.
  static Path _outlineToPath(List<Offset> outline) {
    final path = Path();
    if (outline.isEmpty) return path;

    if (outline.length < 2) {
      path.addOval(Rect.fromCircle(center: outline.first, radius: 1));
      return path;
    }

    final first = outline.first;
    path.moveTo(first.dx, first.dy);

    for (var i = 0; i < outline.length; i++) {
      final current = outline[i];
      // El módulo cierra el anillo: el último vértice enlaza con el primero.
      final next = outline[(i + 1) % outline.length];
      path.quadraticBezierTo(
        current.dx,
        current.dy,
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
    }

    path.close();
    return path;
  }

  /// Prepara la brocha con la que se rellena la silueta.
  static Paint buildPaint({
    required ToolType tool,
    required int colorArgb,
  }) {
    final base = Color(colorArgb);
    final paint = Paint()
      // Se rellena el contorno, no se traza: el grosor ya está en la geometría.
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    if (tool == ToolType.highlighter) {
      // `multiply` es lo que hace que un marcador parezca un marcador: oscurece
      // lo que hay debajo en vez de taparlo, así que el texto se sigue leyendo
      // y dos pasadas cruzadas se ven más intensas, igual que en papel.
      paint
        ..color = base.withValues(alpha: 0.35)
        ..blendMode = BlendMode.multiply;
    } else {
      paint.color = base;
    }

    return paint;
  }
}
