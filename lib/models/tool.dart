/// Herramientas de dibujo disponibles en el lienzo.
///
/// El valor `name` de cada entrada es lo que se serializa a JSON, así que
/// renombrar una constante rompería las notas ya guardadas. Si algún día hay
/// que renombrarla, se añade una nueva y se migran los datos.
enum ToolType {
  /// Bolígrafo: el ancho del trazo responde a la presión del lápiz.
  pen,

  /// Marcador: ancho constante y color translúcido, para resaltar sin tapar.
  highlighter,

  /// Borrador por trazo completo: elimina cualquier trazo que toque.
  eraser;

  static ToolType fromName(String name) =>
      ToolType.values.firstWhere((t) => t.name == name, orElse: () => pen);
}

/// Configuración activa de una herramienta: con qué color y grosor dibuja.
///
/// Es inmutable y usa `copyWith` en lugar de setters porque el estado de
/// Riverpod debe reemplazarse, nunca mutarse: si mutáramos el objeto en sitio,
/// Riverpod no detectaría el cambio y la interfaz no se refrescaría.
class ToolSettings {
  const ToolSettings({
    required this.type,
    required this.colorArgb,
    required this.width,
  });

  final ToolType type;

  /// Color en formato ARGB de 32 bits. Se guarda como `int` y no como `Color`
  /// para que el modelo no dependa de Flutter y viaje tal cual al backend.
  final int colorArgb;

  /// Grosor base en píxeles del documento. Para el bolígrafo es el grosor a
  /// presión media; la presión real lo escala al dibujar.
  final double width;

  /// El marcador se dibuja translúcido para que se lea lo que hay debajo.
  /// El bolígrafo siempre es opaco.
  double get opacity => type == ToolType.highlighter ? 0.35 : 1.0;

  /// Grosor real con el que se dibuja.
  ///
  /// El usuario elige un grosor en abstracto (fino, medio, grueso) y cada
  /// herramienta lo interpreta a su escala: un marcador de 3 píxeles no
  /// subrayaría nada, igual que en papel la punta de un fluorescente es mucho
  /// más ancha que la de un bolígrafo.
  double get effectiveWidth =>
      type == ToolType.highlighter ? width * 6 : width;

  /// Solo el bolígrafo modula el grosor con la presión. Un marcador real tiene
  /// una punta de fieltro rígida, así que mantiene el ancho constante.
  bool get isPressureSensitive => type == ToolType.pen;

  ToolSettings copyWith({ToolType? type, int? colorArgb, double? width}) {
    return ToolSettings(
      type: type ?? this.type,
      colorArgb: colorArgb ?? this.colorArgb,
      width: width ?? this.width,
    );
  }

  static const ToolSettings initial = ToolSettings(
    type: ToolType.pen,
    colorArgb: 0xFF1A1A1A, // casi negro: el negro puro cansa la vista
    width: 3.0,
  );
}
