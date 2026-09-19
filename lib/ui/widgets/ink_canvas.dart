import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kroma/models/stroke_builder.dart';
import 'package:kroma/models/stroke_point.dart';
import 'package:kroma/models/tool.dart';
import 'package:kroma/ui/painters/ink_painters.dart';
import 'package:kroma/ui/painters/stroke_picture_cache.dart';
import 'package:kroma/providers/canvas_transform_controller.dart';
import 'package:kroma/providers/ink_provider.dart';

/// El lienzo: captura el lápiz y dibuja las dos capas de tinta.
class InkCanvas extends ConsumerStatefulWidget {
  const InkCanvas({super.key});

  @override
  ConsumerState<InkCanvas> createState() => _InkCanvasState();
}

class _InkCanvasState extends ConsumerState<InkCanvas> {
  /// Radio del borrador en píxeles **de pantalla**.
  ///
  /// Se define en pantalla y no en documento para que el borrador se sienta
  /// siempre del mismo tamaño bajo el dedo, esté el lienzo ampliado o alejado.
  static const double _eraserScreenRadius = 12.0;

  /// Distancia mínima entre puntos capturados, en píxeles de pantalla.
  ///
  /// Filtra el ruido del sensor sin comerse detalle: por debajo de un par de
  /// píxeles, lo que llega es temblor del dispositivo, no intención del que
  /// escribe. Además recorta bastante el tamaño final del trazo.
  static const double _minCaptureDistance = 1.5;

  final StrokePictureCache _cache = StrokePictureCache();

  /// El puntero que está dibujando ahora mismo, si lo hay.
  int? _drawingPointer;

  /// Si el puntero que dibuja es un borrador (por herramienta o por la punta
  /// invertida del lápiz).
  bool _erasing = false;

  /// Hay un lápiz apoyado en la pantalla.
  ///
  /// Mientras esto sea cierto se ignora **todo** evento táctil. Así es como se
  /// resuelve el apoyo de la palma: no hace falta detectar nada ni medir el
  /// tamaño del contacto, basta con dar prioridad absoluta al lápiz.
  bool _stylusActive = false;

  /// Dedos apoyados, con su última posición, para el gesto de pellizco.
  final Map<int, Offset> _touchPoints = {};

  /// Estado del gesto de dos dedos entre eventos consecutivos.
  Offset? _lastFocal;
  double? _lastSpread;

  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }

  // --- Utilidades de entrada ------------------------------------------------

  bool _isStylus(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  /// Lleva la presión del dispositivo al rango 0–1 que espera el motor.
  ///
  /// Cada fabricante reporta su propio rango en `pressureMin`/`pressureMax`,
  /// así que la presión bruta no es comparable entre dispositivos. Los ratones
  /// y las pantallas táctiles sin sensor devuelven siempre el máximo, y por eso
  /// aquí se les asigna un valor intermedio fijo: su grosor lo decidirá después
  /// la simulación por velocidad.
  double _normalizePressure(PointerEvent event) {
    if (!_isStylus(event.kind)) return StrokePoint.defaultPressure;

    final range = event.pressureMax - event.pressureMin;
    if (range <= 0) return StrokePoint.defaultPressure;

    final normalized = (event.pressure - event.pressureMin) / range;
    return normalized.clamp(0.0, 1.0);
  }

  /// Decide si este puntero puede dibujar.
  bool _canDraw(PointerDeviceKind kind, bool drawWithTouch) {
    if (_isStylus(kind)) return true;
    return drawWithTouch;
  }

  // --- Ciclo de vida del trazo ----------------------------------------------

  void _onPointerDown(PointerDownEvent event) {
    final state = ref.read(inkCanvasProvider);
    final transform = ref.read(canvasTransformProvider);
    final live = ref.read(liveStrokeProvider);

    if (_isStylus(event.kind)) {
      _stylusActive = true;
      // El lápiz manda. Si ya había un trazo en marcha solo puede haberlo
      // empezado un dedo o el ratón, así que se descarta: es exactamente lo que
      // pasa al apoyar la mano un instante antes que la punta del lápiz.
      if (_drawingPointer != null) {
        if (_erasing) {
          ref.read(inkCanvasProvider.notifier).endErase();
        } else {
          live.cancel();
        }
        _drawingPointer = null;
        _erasing = false;
      }
      _touchPoints.clear();
      _resetGesture();
    } else if (event.kind == PointerDeviceKind.touch) {
      if (_stylusActive) return; // rechazo de palma

      _touchPoints[event.pointer] = event.localPosition;

      if (_touchPoints.length >= 2) {
        // Segundo dedo: el usuario quiere hacer zoom, no escribir. Se descarta
        // el trazo que hubiera empezado el primer dedo.
        if (_drawingPointer != null) {
          live.cancel();
          _drawingPointer = null;
          _erasing = false;
        }
        _resetGesture();
        return;
      }
    }

    if (_drawingPointer != null) return;
    if (!_canDraw(event.kind, state.drawWithTouch)) return;

    // La punta invertida del lápiz borra, igual que al darle la vuelta a un
    // lapicero de verdad. Es gratis de implementar y se descubre solo.
    final useEraser = state.tool.type == ToolType.eraser ||
        event.kind == PointerDeviceKind.invertedStylus;

    _drawingPointer = event.pointer;
    _erasing = useEraser;

    final documentPoint = transform.toDocument(event.localPosition);

    if (useEraser) {
      ref.read(inkCanvasProvider.notifier).beginErase();
      _eraseAt(documentPoint);
      return;
    }

    live.begin(
      StrokeBuilder(
        tool: state.tool.type,
        colorArgb: state.tool.colorArgb,
        baseWidth: state.tool.effectiveWidth,
        hasRealPressure: _isStylus(event.kind),
      ),
    );
    live.extend(
      x: documentPoint.dx,
      y: documentPoint.dy,
      pressure: _normalizePressure(event),
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    final transform = ref.read(canvasTransformProvider);

    // Gesto de dos dedos: desplazar y ampliar.
    if (event.kind == PointerDeviceKind.touch &&
        _touchPoints.containsKey(event.pointer)) {
      _touchPoints[event.pointer] = event.localPosition;
      if (_touchPoints.length >= 2) {
        _updatePinch(transform);
        return;
      }
    }

    if (event.pointer != _drawingPointer) return;

    final documentPoint = transform.toDocument(event.localPosition);

    if (_erasing) {
      _eraseAt(documentPoint);
      return;
    }

    ref.read(liveStrokeProvider).extend(
          x: documentPoint.dx,
          y: documentPoint.dy,
          pressure: _normalizePressure(event),
          // El umbral se convierte a documento: con el lienzo alejado, un mismo
          // gesto recorre más documento y un umbral fijo perdería detalle real.
          minDistance: transform.minCaptureDistance(_minCaptureDistance),
        );
  }

  void _onPointerUp(PointerUpEvent event) {
    _touchPoints.remove(event.pointer);
    if (_isStylus(event.kind)) _stylusActive = false;
    if (_touchPoints.length < 2) _resetGesture();

    if (event.pointer != _drawingPointer) return;
    _finishStroke();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _touchPoints.remove(event.pointer);
    if (_isStylus(event.kind)) _stylusActive = false;
    _resetGesture();

    if (event.pointer != _drawingPointer) return;

    // Cancelado por el sistema (una llamada entrante, un gesto desde el borde).
    // El trazo se descarta en lugar de guardarse a medias.
    ref.read(liveStrokeProvider).cancel();
    if (_erasing) ref.read(inkCanvasProvider.notifier).endErase();
    _drawingPointer = null;
    _erasing = false;
  }

  void _finishStroke() {
    final notifier = ref.read(inkCanvasProvider.notifier);

    if (_erasing) {
      notifier.endErase();
    } else {
      // Aquí es donde el trazo mutable se congela en uno inmutable.
      final builder = ref.read(liveStrokeProvider).finish();
      final stroke = builder?.build();
      if (stroke != null) notifier.commitStroke(stroke);
    }

    _drawingPointer = null;
    _erasing = false;
  }

  void _eraseAt(Offset documentPoint) {
    final transform = ref.read(canvasTransformProvider);
    ref.read(inkCanvasProvider.notifier).eraseAt(
          x: documentPoint.dx,
          y: documentPoint.dy,
          // El radio de pantalla pasa a documento para que el borrador tenga
          // siempre el mismo tamaño aparente bajo el dedo.
          radius: _eraserScreenRadius / transform.scale,
        );
  }

  // --- Desplazamiento y zoom ------------------------------------------------

  void _resetGesture() {
    _lastFocal = null;
    _lastSpread = null;
  }

  /// Traduce las posiciones de dos o más dedos en desplazamiento y zoom.
  ///
  /// El **centro** de los dedos moviéndose es desplazamiento; la **separación**
  /// entre ellos creciendo o menguando es zoom. Se trabaja siempre con la
  /// diferencia respecto al evento anterior, no con valores absolutos, para que
  /// añadir o levantar un dedo a media maniobra no dé un salto brusco.
  void _updatePinch(CanvasTransformController transform) {
    final points = _touchPoints.values.toList();

    var sumX = 0.0;
    var sumY = 0.0;
    for (final p in points) {
      sumX += p.dx;
      sumY += p.dy;
    }
    final focal = Offset(sumX / points.length, sumY / points.length);

    // Separación media de los dedos respecto a su centro.
    var spread = 0.0;
    for (final p in points) {
      spread += (p - focal).distance;
    }
    spread /= points.length;

    final previousFocal = _lastFocal;
    final previousSpread = _lastSpread;

    if (previousFocal != null && previousSpread != null && previousSpread > 0) {
      transform.applyGesture(
        panDelta: focal - previousFocal,
        scaleFactor: spread / previousSpread,
        focalScreen: focal,
      );
    }

    _lastFocal = focal;
    _lastSpread = spread;
  }

  /// Rueda del ratón: desplaza, y amplía con Ctrl pulsado.
  ///
  /// Es la convención de Figma, Photoshop y los navegadores, así que no hay que
  /// aprender nada nuevo.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final transform = ref.read(canvasTransformProvider);

    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      // Exponencial y no lineal: así cada muesca de la rueda cambia el zoom en
      // la misma proporción, que es como lo percibe el ojo. Con un incremento
      // fijo, ampliar sería lentísimo de cerca y brusco de lejos.
      final factor = math.exp(-event.scrollDelta.dy / 250);
      transform.zoomBy(factor, event.localPosition);
    } else {
      transform.pan(-event.scrollDelta);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strokes = ref.watch(inkCanvasProvider.select((s) => s.strokes));
    final transform = ref.watch(canvasTransformProvider);
    final live = ref.watch(liveStrokeProvider);

    return Listener(
      // `opaque` hace que el lienzo reciba eventos también donde no hay nada
      // dibujado. Sin esto solo respondería sobre píxeles pintados.
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onPointerSignal: _onPointerSignal,
      child: ColoredBox(
        color: const Color(0xFFFDFDFB), // papel, no blanco puro
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Cada capa va en su propia `RepaintBoundary`, y esto es lo que
            // hace que la separación funcione de verdad. Sin ellas, las dos
            // compartirían capa de composición y repintar el trazo en curso
            // arrastraría consigo a los cientos de trazos de debajo, anulando
            // todo el beneficio.
            RepaintBoundary(
              child: CustomPaint(
                painter: ConfirmedStrokesPainter(
                  strokes: strokes,
                  cache: _cache,
                  transform: transform,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: LiveStrokePainter(live: live, transform: transform),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
