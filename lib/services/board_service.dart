import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kroma/services/api_client.dart';
import 'package:kroma/providers/api_providers.dart';
import 'package:kroma/models/stroke.dart';
import 'package:kroma/models/board_models.dart';
import 'package:kroma/services/stroke_mapper.dart';

/// Acceso a tableros, tarjetas y tinta.
class BoardService {
  const BoardService(this._api);

  final ApiClient _api;

  Future<List<BoardSummary>> listBoards() async {
    final data = await _api.get('/boards');
    return (data as List)
        .map((b) => BoardSummary.fromJson(b as Map<String, dynamic>))
        .toList();
  }

  Future<BoardDetail> getBoard(String boardId) async {
    final data = await _api.get('/boards/$boardId');
    return BoardDetail.fromJson(data as Map<String, dynamic>);
  }

  Future<BoardSummary> createBoard(String title) async {
    final data = await _api.post('/boards', body: {'title': title});
    return BoardSummary.fromJson(data as Map<String, dynamic>);
  }

  Future<NoteCard> createCard({
    required String columnId,
    required String title,
    double? position,
  }) async {
    final data = await _api.post('/columns/$columnId/cards', body: {
      'title': title,
      // El marcador `?` omite la clave cuando el valor es nulo. Importa: sin
      // posición, el servidor coloca la tarjeta al final, mientras que mandar
      // `"position": null` sería un valor explícito y fallaría al convertirlo.
      'position': ?position,
    });
    return NoteCard.fromJson(data as Map<String, dynamic>);
  }

  Future<void> updateCard({required String cardId, required String title}) =>
      _api.put('/cards/$cardId', body: {'title': title});

  Future<void> moveCard({
    required String cardId,
    required String targetColumnId,
    required double position,
  }) =>
      _api.post('/cards/$cardId/move', body: {
        'targetColumnId': targetColumnId,
        'position': position,
      });

  Future<void> deleteCard(String cardId) => _api.delete('/cards/$cardId');

  Future<List<Stroke>> getStrokes(String cardId) async {
    final data = await _api.get('/cards/$cardId/strokes');
    return (data as List)
        .map((s) => StrokeMapper.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// Envía en una sola petición los trazos nuevos y los borrados.
  ///
  /// Un único viaje en vez de uno por trazo. Escribiendo se generan decenas de
  /// trazos en segundos, y una petición por cada uno castigaría la batería y la
  /// red del móvil, además de multiplicar por decenas el coste de cada arranque
  /// en frío del servidor.
  Future<void> syncStrokes({
    required String cardId,
    List<Stroke> added = const [],
    List<String> deletedIds = const [],
  }) async {
    if (added.isEmpty && deletedIds.isEmpty) return;

    await _api.post('/cards/$cardId/strokes/sync', body: {
      'added': added.map(StrokeMapper.toJson).toList(),
      'deletedIds': deletedIds,
    });
  }
}

final boardServiceProvider = Provider<BoardService>(
  (ref) => BoardService(ref.watch(apiClientProvider)),
);
