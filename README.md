# Kroma

Notas manuscritas organizadas en tableros: la escritura a mano de GoodNotes con la
organización de Notion.

Escribe con lápiz dentro de las tarjetas de un tablero **Por hacer / Haciendo / Hecho**.

## Qué es cada cosa

- **`kroma`** (este repositorio): la aplicación, hecha con Flutter. Funciona en Android y en
  el navegador, y se desarrolla en Windows.
- **`KromaApi`**: el backend, hecho con C# y ASP.NET Core sobre PostgreSQL.

## Estructura

```
lib/
  models/      clases de datos: trazos, tableros, tarjetas
  services/    acceso a la API y almacenamiento del token
  providers/   estado de la aplicación (Riverpod)
  ui/
    screens/   pantallas completas
    widgets/   componentes reutilizables
    painters/  dibujado del lienzo de tinta
```

## Ponerlo en marcha

Arranca antes el backend (`dotnet run` en el repositorio `KromaApi`) y después:

```bash
flutter pub get
flutter run -d chrome     # navegador
flutter run -d windows    # escritorio, requiere Modo Desarrollador de Windows
```

Para apuntar a un servidor que no sea el local:

```bash
flutter run --dart-define=API_BASE_URL=https://tu-servidor.onrender.com
```

En el emulador de Android, `localhost` es el propio emulador: la app usa
automáticamente `10.0.2.2`, que apunta a tu ordenador.

## Pruebas

```bash
flutter test
flutter analyze
```
