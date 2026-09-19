import 'package:flutter/foundation.dart';

/// Dónde vive la API.
class ApiConfig {
  const ApiConfig._();

  /// Dirección base, configurable al compilar.
  ///
  /// Se lee con `String.fromEnvironment`, que resuelve en tiempo de
  /// compilación, así que para apuntar al servidor de producción basta con:
  ///
  /// ```
  /// flutter run --dart-define=API_BASE_URL=https://notes-api.onrender.com
  /// ```
  ///
  /// La alternativa sería un archivo de configuración leído al arrancar, pero
  /// entonces la dirección viajaría dentro de los assets y habría que
  /// gestionar su carga antes de la primera petición.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// Dirección efectiva: la configurada, o la de desarrollo si no hay ninguna.
  static String get effectiveBaseUrl =>
      baseUrl.isNotEmpty ? baseUrl : _developmentBaseUrl;

  /// Dirección del backend en local, que **depende de la plataforma**.
  ///
  /// Es una de esas cosas que hacen perder una tarde la primera vez. Para el
  /// navegador y para Windows, el servidor está en `localhost`. Pero dentro del
  /// emulador de Android, `localhost` es el propio teléfono emulado, no tu
  /// ordenador: hay que usar `10.0.2.2`, una dirección especial que el emulador
  /// redirige a la máquina anfitriona.
  ///
  /// En un móvil físico conectado por USB no sirve ninguna de las dos: hay que
  /// poner la IP de tu ordenador en la red local (algo como 192.168.1.40) y
  /// pasarla con `--dart-define`.
  static String get _developmentBaseUrl {
    const port = 5212;
    if (kIsWeb) return 'http://localhost:$port';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:$port';
    }
    return 'http://localhost:$port';
  }

  /// Tiempo máximo de espera al conectar.
  ///
  /// Generoso a propósito. El plan gratuito de Render duerme el servicio tras
  /// quince minutos sin uso, y despertarlo lleva cerca de un minuto. Con el
  /// tiempo de espera por defecto, la primera petición del día fallaría siempre
  /// y parecería que la app está rota.
  static const Duration connectTimeout = Duration(seconds: 70);

  static const Duration receiveTimeout = Duration(seconds: 30);
}
