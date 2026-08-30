# Prueba de ANR en campo (Android)

Application ID verificado en `android/app/build.gradle.kts`: `com.aquafim.ddr001diag`.

## Preparación

Usar una compilación `profile` equivalente a campo y un cable USB confiable. No borrar datos de la aplicación: los diagnósticos y fotografías pendientes deben conservarse.

```powershell
adb devices -l
adb shell pidof com.aquafim.ddr001diag
adb logcat -c
```

Iniciar captura antes de reproducir:

```powershell
adb logcat -v threadtime > anr-logcat-threadtime.txt
```

En el S23 Ultra, con modo avión activo y los datos reales intactos:

1. Abrir una revisión visual existente.
2. Escribir comentario, cambiar Sí/No y avanzar/retroceder de paso.
3. Abrir cámara, tomar fotografía y volver a la misma pantalla.
4. Repetir varias capturas consecutivas mientras se observa “Procesando fotografía...”.
5. Si Android presenta “no responde”, no cerrar la app; seleccionar “Esperar” una vez y capturar inmediatamente los datos siguientes.

## Captura al aparecer el ANR

En otra terminal:

```powershell
adb shell dumpsys activity lastanr > anr-lastanr.txt
adb logcat -d -v threadtime > anr-logcat-final.txt
adb shell dumpsys meminfo com.aquafim.ddr001diag > anr-meminfo.txt
adb shell dumpsys cpuinfo > anr-cpuinfo.txt
adb shell pidof com.aquafim.ddr001diag
```

Con el PID devuelto (sustituir `<PID>`):

```powershell
adb shell top -b -n 1 -H -p <PID> > anr-threads-cpu.txt
adb shell cat /proc/<PID>/status > anr-process-status.txt
adb shell cat /proc/<PID>/limits > anr-process-limits.txt
```

Para obtener stacks Java/Android sin terminar el proceso:

```powershell
adb shell kill -3 <PID>
adb logcat -d -v threadtime > anr-after-sigquit.txt
```

Detener la captura continua con `Ctrl+C`. No ejecutar `pm clear`, desinstalar, limpiar Hive ni borrar el directorio de la aplicación.

## Perfil Flutter

Ejecutar en profile y abrir DevTools desde la URL que reporte Flutter:

```powershell
flutter run --profile
```

En Performance registrar el intervalo cámara → retorno → fotografía persistida. En Memory tomar snapshots antes de abrir cámara, durante “Procesando fotografía...” y después de guardar. Correlacionar con logs sanitizados:

```text
[PERF][PHOTO] picker_return_ms=...
[PERF][PHOTO] normalize_ms=...
[PERF][PHOTO] validate_ms=...
[PERF][PHOTO] thumbnail_ms=...
[PERF][PHOTO] hash_ms=...
[PERF][PHOTO] persist_ms=...
[PERF][PHOTO] draft_save_ms=...
[PERF][PHOTO] total_ms=...
```

Los archivos de evidencia pueden contener identificadores del dispositivo o infraestructura. Compartirlos sólo por el canal autorizado y no adjuntarlos al repositorio.
