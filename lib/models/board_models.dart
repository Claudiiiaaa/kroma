/// Resumen de un tablero, para listarlos sin descargar su contenido.
class BoardSummary {
  const BoardSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.cardCount,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final int cardCount;

  factory BoardSummary.fromJson(Map<String, dynamic> json) => BoardSummary(
        id: json['id'] as String,
        title: json['title'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        cardCount: (json['cardCount'] as num?)?.toInt() ?? 0,
      );
}

/// Un tablero con sus columnas y tarjetas, pero sin la tinta.
///
/// La tinta se pide aparte, al abrir cada tarjeta. Traerla con el tablero
/// significaría descargar cientos de miles de puntos para enseñar una pantalla
/// donde no se ve ni un trazo.
class BoardDetail {
  const BoardDetail({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.columns,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final List<BoardColumn> columns;

  factory BoardDetail.fromJson(Map<String, dynamic> json) => BoardDetail(
        id: json['id'] as String,
        title: json['title'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        columns: (json['columns'] as List)
            .map((c) => BoardColumn.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  BoardDetail copyWith({String? title, List<BoardColumn>? columns}) =>
      BoardDetail(
        id: id,
        title: title ?? this.title,
        updatedAt: updatedAt,
        columns: columns ?? this.columns,
      );
}

class BoardColumn {
  const BoardColumn({
    required this.id,
    required this.title,
    required this.position,
    required this.cards,
  });

  final String id;
  final String title;
  final double position;
  final List<NoteCard> cards;

  factory BoardColumn.fromJson(Map<String, dynamic> json) => BoardColumn(
        id: json['id'] as String,
        title: json['title'] as String,
        position: (json['position'] as num).toDouble(),
        cards: (json['cards'] as List)
            .map((c) => NoteCard.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  BoardColumn copyWith({String? title, List<NoteCard>? cards}) => BoardColumn(
        id: id,
        title: title ?? this.title,
        position: position,
        cards: cards ?? this.cards,
      );
}

/// Una tarjeta del tablero.
///
/// Se llama `NoteCard` y no `Card` porque `Card` ya es un widget de Material, y
/// tener dos cosas con el mismo nombre en la misma pantalla obligaría a
/// renombrar una de las dos en cada importación.
class NoteCard {
  const NoteCard({
    required this.id,
    required this.columnId,
    required this.title,
    required this.position,
    required this.updatedAt,
    required this.strokeCount,
  });

  final String id;
  final String columnId;
  final String title;
  final double position;
  final DateTime updatedAt;

  /// Cuántos trazos tiene su lienzo.
  ///
  /// Llega con el tablero para poder marcar las tarjetas que llevan notas a
  /// mano sin descargar la tinta de todas ellas.
  final int strokeCount;

  bool get hasInk => strokeCount > 0;

  factory NoteCard.fromJson(Map<String, dynamic> json) => NoteCard(
        id: json['id'] as String,
        columnId: json['columnId'] as String,
        title: json['title'] as String,
        position: (json['position'] as num).toDouble(),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        strokeCount: (json['strokeCount'] as num?)?.toInt() ?? 0,
      );

  NoteCard copyWith({
    String? columnId,
    String? title,
    double? position,
    int? strokeCount,
  }) =>
      NoteCard(
        id: id,
        columnId: columnId ?? this.columnId,
        title: title ?? this.title,
        position: position ?? this.position,
        updatedAt: updatedAt,
        strokeCount: strokeCount ?? this.strokeCount,
      );
}
