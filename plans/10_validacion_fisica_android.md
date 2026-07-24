# Validación física Android

Fecha: 2026-07-23.

- Dispositivo: Pixel 7 Pro, serie `27301FDH3004R7`, autorizado por ADB.
- Android: 17 (API 37), `android-arm64`.
- Flutter: 3.44.5.
- Dart: 3.12.2.
- ADB: `C:\Users\Martin\AppData\Local\Android\Sdk\platform-tools\adb.exe`.
- ADB 1.0.41, plataforma 36.0.0-13206524.
- API base: red local, puerto 3000 (IP no registrada).
- Cuenta de prueba: no utilizada.

## Resultado

En la comprobación final, `adb devices -l` detectó y autorizó el Pixel. `flutter doctor
-v` terminó sin problemas y validó Flutter, Windows, Android SDK 36.1.0, JDK 21 y
licencias. `flutter devices` listó el Pixel y tres destinos de escritorio/web.

No se ejecutó `flutter run`, login ni recorrido manual; la presencia del dispositivo no
se presenta como validación física del flujo.

| Paso | Resultado |
|---|---|
| Arranque/login | Pendiente: dispositivo disponible, recorrido no ejecutado |
| Inicio/Nueva revisión | Pendiente |
| Búsqueda/selección | Pendiente |
| Checklist RV v2 | Pendiente |
| GPS/fotografía | Pendiente |
| Cierre/reapertura | Pendiente |
| Offline/sincronización | Pendiente |
| Mapa/contador | Pendiente |
| Preselección | Cubierta automáticamente; validación física pendiente |

## Validación automatizada posterior

La navegación desde mapa fue corregida mediante una función única que codifica
`hydrantId`; GoRouter entrega el query parameter a `NewSurveyPage`, que coloca el
hidrante primero y muestra “Hidrante seleccionado desde el mapa”. También se cubren
ruta sin identificador e identificador inexistente.

- `dart format lib test`: 142 archivos, finalizó correctamente.
- `flutter analyze`: sin observaciones.
- `flutter test`: 123/123 aprobadas.
- `flutter build apk --debug`: aprobado; APK en la salida estándar ignorada por Git.
- `CupertinoIcons`: no se usa en `lib`, `test` ni `integration_test`; no se agregó una
  dependencia innecesaria.
- `flutter_image_compress_common 1.1.0`: advertencia futura sobre KGP; no bloquea el
  build. El proyecto usa Kotlin 2.3.20. Revisar actualización del plugin en otra tarea.

La validación física continúa separada y pendiente hasta ejecutar el recorrido manual.

## Bloqueo y preparación

ADB fue localizado y el Pixel está conectado/autorizado. No es necesario modificar
`PATH`; usar la ruta absoluta. Para una sesión física separada, determinar primero la
IPv4 real del equipo y ejecutar:

```powershell
flutter run --dart-define=APP_ENV=development `
  --dart-define=API_BASE_URL=http://IP_REAL:3000/api/v1
```

Se generó únicamente el APK debug estándar, ignorado por Git. No se modificó versión,
package, firma ni diseño.
