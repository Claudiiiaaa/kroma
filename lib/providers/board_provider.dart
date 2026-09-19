import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kroma/services/board_service.dart';
import 'package:kroma/models/board_models.dart';

/// Separación entre posiciones al añadir al principio o al final.
const double _positionGap = 1000;

final boardControllerProvider =
    AsyncNotifierProvider<BoardController, BoardDetail>(BoardController.new);

/// Gestiona el tablero abierto: sus columnas, sus tarjetas y los movimientos.
class BoardController extends AsyncNotifier<BoardDetail> {
  BoardService get _repository => ref.read(boardServiceProvider);

  @override
  Future<BoardDetail> build() async {
    final boards = await _repository.listBoards();

    // Al registrarse, el servidor crea un tablero con sus tres columnas. Si aun
    // así no hubiera ninguno —una cuenta antigua, o alguien que borró el
    // suyo—, se crea uno para que la app nunca muestre una pantalla vacía sin
    // salida.
    final boardId = boards.isEmpty
        ? (await _repository.createBoard('Mi tablero')).id
        : boards.first.id;

    return _repository.getBoard(boardId);
  }

  Future<void> refresh() async {
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }

    state = await AsyncValue.guard(() => _repository.getBoard(current.id));
  }

  /// Abre otro tablero de la misma cuenta.
  Future<void> openBoard(String boardId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.getBoard(boardId));
  }

  Future<void> createBoard(String title) async {
    final created = await _repository.createBoard(title);
    await openBoard(created.id);
  }

  // --- Tarjetas -------------------------------------------------------------

  Future<void> addCard({required String columnId, required String title}) async {
    final board = state.value;
    if (board == null) return;

    // Aquí no se hace actualización optimista: la tarjeta necesita el
    // identificador que genera el servidor para poder abrirla después, así que
    // se espera la respuesta. Es una operación puntual y con pulsación, donde
    // una espera breve no molesta; arrastrar es otra cosa.
    final card = await _repository.createCard(columnId: columnId, title: title);

    state = AsyncData(_replaceColumn(board, columnId, (column) {
      return column.copyWith(cards: [...column.cards, card]);
    }));
  }

  Future<void> renameCard({
    required String cardId,
    required String columnId,
    required String title,
  }) async {
    final board = state.value;
    if (board == null) return;

    final previous = board;

    // Se aplica ya en pantalla y se envía después: escribir un título y esperar
    // a que el servidor conteste para verlo cambiar se siente lento.
    state = AsyncData(_replaceColumn(board, columnId, (column) {
      return column.copyWith(cards: [
        for (final c in column.cards)
          if (c.id == cardId) c.copyWith(title: title) else c,
      ]);
    }));

    try {
      await _repository.updateCard(cardId: cardId, title: title);
    } catch (_) {
      // Si falla, se deshace el cambio en pantalla. Dejarlo puesto sería peor
      // que no haberlo aplicado: el usuario creería que se guardó.
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> deleteCard({
    required String cardId,
    required String columnId,
  }) async {
    final board = state.value;
    if (board == null) return;

    final previous = board;

    state = AsyncData(_replaceColumn(board, columnId, (column) {
      return column.copyWith(
        cards: column.cards.where((c) => c.id != cardId).toList(),
      );
    }));

    try {
      await _repository.deleteCard(cardId);
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  /// Mueve una tarjeta a otra columna o a otro lugar de la suya.
  ///
  /// [targetIndex] es la posición que debe ocupar en la columna de destino una
  /// vez retirada de donde estaba.
  Future<void> moveCard({
    required String cardId,
    required String targetColumnId,
    required int targetIndex,
  }) async {
    final board = state.value;
    if (board == null) return;

    final card = _findCard(board, cardId);
    if (card == null) return;

    final previous = board;

    // La tarjeta se quita de todas las columnas antes de calcular nada. Si
    // sigue en la lista mientras se busca su hueco, al moverla dentro de su
    // propia columna acabaría comparándose consigo misma y el resultado sería
    // una posición que no cambia nada.
    final withoutCard = [
      for (final column in board.columns)
        column.copyWith(
          cards: column.cards.where((c) => c.id != cardId).toList(),
        ),
    ];

    final target = withoutCard.firstWhere((c) => c.id == targetColumnId);
    final index = targetIndex.clamp(0, target.cards.length);
    final position = _positionFor(target.cards, index);

    final moved = card.copyWith(columnId: targetColumnId, position: position);

    state = AsyncData(board.copyWith(
      columns: [
        for (final column in withoutCard)
          if (column.id == targetColumnId)
            column.copyWith(cards: [...column.cards]..insert(index, moved))
          else
            column,
      ],
    ));

    try {
      await _repository.moveCard(
        cardId: cardId,
        targetColumnId: targetColumnId,
        position: position,
      );
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  /// Actualiza el contador de trazos tras editar el lienzo de una tarjeta.
  void updateStrokeCount({required String cardId, required int strokeCount}) {
    final board = state.value;
    if (board == null) return;

    state = AsyncData(board.copyWith(
      columns: [
        for (final column in board.columns)
          column.copyWith(cards: [
            for (final c in column.cards)
              if (c.id == cardId) c.copyWith(strokeCount: strokeCount) else c,
          ]),
      ],
    ));
  }

  // --- Auxiliares -----------------------------------------------------------

  /// Calcula la posición para insertar en [index] de una lista ya ordenada.
  ///
  /// Es la contrapartida en el cliente de las posiciones decimales del
  /// servidor: en vez de renumerar toda la columna, la tarjeta recibe un valor
  /// intermedio entre sus dos futuras vecinas y solo cambia una fila.
  static double _positionFor(List<NoteCard> cards, int index) {
    if (cards.isEmpty) return _positionGap;
    if (index <= 0) return cards.first.position - _positionGap;
    if (index >= cards.length) return cards.last.position + _positionGap;
    return (cards[index - 1].position + cards[index].position) / 2;
  }

  static NoteCard? _findCard(BoardDetail board, String cardId) {
    for (final column in board.columns) {
      for (final card in column.cards) {
        if (card.id == cardId) return card;
      }
    }
    return null;
  }

  static BoardDetail _replaceColumn(
    BoardDetail board,
    String columnId,
    BoardColumn Function(BoardColumn column) update,
  ) {
    return board.copyWith(
      columns: [
        for (final column in board.columns)
          if (column.id == columnId) update(column) else column,
      ],
    );
  }
}
