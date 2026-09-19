/// Un punto capturado del lápiz dentro de un trazo.
///
/// Las coordenadas están **siempre en el espacio del documento**, nunca en el
/// de la pantalla. Es la regla más importante del motor: si guardáramos
/// coordenadas de pantalla, los trazos se descolocarían al hacer zoom o
/// desplazar el lienzo, porque el mismo punto del papel tendría coordenadas
/// distintas según cómo estuviera mirándolo el usuario en ese momento.
class StrokePoint {
  const StrokePoint({
    required this.x,
    required this.y,
    required this.pressure,
    required this.tMs,
  });

  final double x;
  final double y;

  /// Presión normalizada entre 0 y 1.
  ///
  /// Flutter la entrega en el rango bruto del dispositivo, que varía entre
  /// fabricantes, así que se normaliza al capturarla. Los ratones y las
  /// pantallas táctiles sin sensor de presión reportan siempre 1.0, y por eso
  /// existe [defaultPressure]: un valor intermedio que produce un trazo con
  /// aspecto natural cuando no hay presión real que medir.
  final double pressure;

  /// Milisegundos transcurridos desde el inicio del trazo.
  ///
  /// Todavía no se usa para dibujar, pero se captura desde ya porque no se
  /// puede recuperar a posteriori. Habilita dos cosas más adelante: reproducir
  /// la escritura como una animación, y modular el grosor según la velocidad.
  final int tMs;

  /// Presión asumida cuando el dispositivo no la mide (ratón o dedo).
  static const double defaultPressure = 0.5;

  StrokePoint copyWith({double? x, double? y, double? pressure, int? tMs}) {
    return StrokePoint(
      x: x ?? this.x,
      y: y ?? this.y,
      pressure: pressure ?? this.pressure,
      tMs: tMs ?? this.tMs,
    );
  }

  /// Se serializa como una lista de 4 números en vez de un objeto con claves.
  ///
  /// Un trazo largo tiene cientos de puntos, y `{"x":1,"y":2,"pressure":0.5,
  /// "tMs":10}` ocupa unas seis veces más que `[1,2,0.5,10]`. Con miles de
  /// trazos sincronizándose, esa diferencia se nota en la factura de datos de
  /// tu hermana y en los 0,5 GB gratuitos de Neon.
  List<num> toJson() => [x, y, pressure, tMs];

  factory StrokePoint.fromJson(List<dynamic> json) {
    return StrokePoint(
      x: (json[0] as num).toDouble(),
      y: (json[1] as num).toDouble(),
      pressure: (json[2] as num).toDouble(),
      tMs: (json[3] as num).toInt(),
    );
  }

  @override
  String toString() =>
      'StrokePoint(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, '
      'p: ${pressure.toStringAsFixed(2)}, t: $tMs)';
}
