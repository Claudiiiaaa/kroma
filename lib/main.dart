import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kroma/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Remuestrea los eventos del puntero para alinearlos con el refresco de la
  // pantalla. El sensor táctil y la pantalla van a frecuencias distintas y sin
  // sincronizar, así que los eventos en crudo llegan repartidos de forma
  // irregular entre fotogramas: unos traen tres puntos y el siguiente ninguno.
  // Eso se ve como un trazo que avanza a tirones aunque la app vaya a 60 fps.
  // Con esto activado, Flutter interpola las posiciones al instante exacto de
  // cada fotograma y el trazo sale continuo. Es una línea que se nota mucho.
  GestureBinding.instance.resamplingEnabled = true;

  // `ProviderScope` es el contenedor donde viven todos los providers de
  // Riverpod. Tiene que envolver a toda la app: cualquier widget que intente
  // leer un provider desde fuera de él lanzará un error en tiempo de ejecución.
  runApp(const ProviderScope(child: NotesApp()));
}
