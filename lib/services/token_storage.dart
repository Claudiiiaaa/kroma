import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda el token de sesión entre arranques de la app.
///
/// Usa el almacén seguro del sistema —el llavero en Android, WebCrypto en el
/// navegador— en lugar de `SharedPreferences`. El token permite entrar en la
/// cuenta durante treinta días sin contraseña, así que guardarlo en texto plano
/// dejaría que cualquier otra app con acceso al almacenamiento lo leyera.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _tokenKey = 'auth_token';

  final FlutterSecureStorage _storage;

  /// Copia en memoria, para no ir al almacén del sistema en cada petición.
  ///
  /// Leer del llavero implica una llamada al sistema operativo, y esto se
  /// consulta en cada una de las peticiones. La caché la mantiene esta misma
  /// clase, así que no puede quedar desincronizada con lo guardado.
  String? _cached;
  bool _loaded = false;

  Future<String?> read() async {
    if (_loaded) return _cached;

    try {
      _cached = await _storage.read(key: _tokenKey);
    } on Exception {
      // El almacén seguro puede fallar: en un navegador en modo incógnito, con
      // las cookies bloqueadas, o en un Android con el llavero corrupto. Que no
      // se pueda recordar la sesión es un incordio; que la app no arranque, un
      // fallo. Se trata como «no hay sesión».
      _cached = null;
    }

    _loaded = true;
    return _cached;
  }

  Future<void> write(String token) async {
    _cached = token;
    _loaded = true;
    try {
      await _storage.write(key: _tokenKey, value: token);
    } on Exception {
      // Se sigue adelante con el token en memoria: la sesión funciona hasta
      // cerrar la app, que es mejor que no poder entrar.
    }
  }

  Future<void> clear() async {
    _cached = null;
    _loaded = true;
    try {
      await _storage.delete(key: _tokenKey);
    } on Exception {
      // Ignorado a propósito.
    }
  }
}
