import 'package:flutter/widgets.dart';

/// El desplazamiento y el zoom del lienzo.
///
/// No usamos una `Matrix4` como fuente de verdad, aunque al final haga falta
/// una para pintar. El motivo es que aquí solo hay traslación y escala
/// uniforme, sin rotación ni sesgado, y para ese caso concreto las cuentas son
/// dos líneas:
///
/// ```
/// pantalla  = documento * scale + offset
/// documento = (pantalla - offset) / scale
/// ```
///
/// Invertir una `Matrix4` genérica cuesta bastante más, y esa inversión haría
/// falta en **cada evento del lápiz** para saber dónde cae el punto en el
/// documento. Con esta representación, convertir es una resta y una división.
///
/// Es también un [ChangeNotifier] y no estado de Riverpod, por el mismo motivo
/// que [LiveStrokeController]: un gesto de pellizco genera decenas de cambios
/// por segundo.
class CanvasTransformController extends ChangeNotifier {
  static const double minScale = 0.25;
  static const double maxScale = 8.0;

  double _scale = 1.0;
  Offset _offset = Offset.zero;

  double get scale => _scale;
  Offset get offset => _offset;

  /// Matriz equivalente, para pasársela a `Canvas.transform`.
  ///
  /// El orden importa y es contraintuitivo: las transformaciones se aplican al
  /// revés de como se leen. Aquí el punto primero se escala y luego se
  /// traslada, que es lo que describe la fórmula de arriba.
  Matrix4 get matrix => Matrix4.identity()
    ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
    ..scaleByDouble(_scale, _scale, 1, 1);

  /// Convierte un punto de la pantalla al espacio del documento.
  ///
  /// **Toda** coordenada capturada del lápiz debe pasar por aquí antes de
  /// guardarse. Es el paso que se olvida en casi todas las apps de dibujo
  /// caseras, y el síntoma es inconfundible: dibujas con el lienzo ampliado y
  /// el trazo aparece desplazado o de otro tamaño.
  Offset toDocument(Offset screenPoint) {
    return (screenPoint - _offset) / _scale;
  }

  /// Convierte un punto del documento a coordenadas de pantalla.
  Offset toScreen(Offset documentPoint) {
    return documentPoint * _scale + _offset;
  }

  /// Distancia mínima entre puntos capturados, expresada en documento.
  ///
  /// El filtro de ruido del trazo tiene sentido en píxeles de pantalla (lo que
  /// el ojo distingue), pero los puntos se guardan en documento. Al alejar el
  /// lienzo, un mismo milímetro de mano recorre más documento, así que el
  /// umbral tiene que dividirse por la escala; si no, al alejarse se perdería
  /// detalle real del trazo.
  double minCaptureDistance(double screenPixels) => screenPixels / _scale;

  /// Desplaza el lienzo. [delta] va en píxeles de pantalla.
  void pan(Offset delta) {
    _offset += delta;
    notifyListeners();
  }

  /// Aplica zoom manteniendo fijo el punto [focalScreen] bajo los dedos.
  ///
  /// Sin esa corrección del desplazamiento, el zoom se haría siempre respecto
  /// a la esquina superior izquierda y el contenido se escaparía de debajo de
  /// los dedos, que es exactamente lo que se siente como "roto" al pellizcar.
  void zoomBy(double factor, Offset focalScreen) {
    final newScale = (_scale * factor).clamp(minScale, maxScale);
    if (newScale == _scale) return;

    // El punto del documento bajo el foco debe seguir ahí tras el zoom, así
    // que se despeja el nuevo offset de la ecuación pantalla = doc * s + off.
    final documentFocal = toDocument(focalScreen);
    _scale = newScale;
    _offset = focalScreen - documentFocal * _scale;
    notifyListeners();
  }

  /// Aplica desplazamiento y zoom a la vez, como hace un gesto de pellizco.
  void applyGesture({required Offset panDelta, required double scaleFactor, required Offset focalScreen}) {
    _offset += panDelta;
    if (scaleFactor != 1.0) {
      zoomBy(scaleFactor, focalScreen);
    } else {
      notifyListeners();
    }
  }

  void reset() {
    _scale = 1.0;
    _offset = Offset.zero;
    notifyListeners();
  }
}
