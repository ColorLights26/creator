> Para: conocer el alcance comprobado de la ampliación de Creator. Lee aquí antes de aprobarla para producción.

# Verificación del 25 de septiembre de 2026

La ampliación funcional está implementada. **La aceptación completa del plan
sigue pendiente de las pruebas físicas y de coste sostenido.** Ninguno de los
ejemplos nuevos se aprobó para la app principal.

| Recorrido | Resultado observado |
| --- | --- |
| iOS Studio, compilación e instalación | Correctas; Liquid Chrome visible a pantalla completa en el simulador dedicado. |
| Android | APK debug compilado, también desde un kit independiente sin cachés. No hubo Android físico conectado. |
| Crear sin registros manuales | En la copia independiente se copiaron las dos plantillas como una pareja nueva; el build descubrió el noveno visual automáticamente. |
| Programas C++ | ASan/UBSan y timeout; los cuatro ejemplos pasan repetición determinista, dos instancias intercaladas, pausa/reset y coherencia ambiental a 30/60 FPS. |
| Pasadas por cuadro (6 de octubre de 2026) | El contador de `authored_probe.cpp` coincide con el harness de Metal en los 277 visuales nativos: máximo de pasadas y de bytes idénticos en iPhone e iPad, 0 diferencias (repetido con el límite por superficie, y en una muestra de 30 con `check_native.py --pass-report harness`). El gate exige el límite de cada superficie (35 pasadas en el iPhone y 28 en el iPad, nunca más de 128 MiB). Sobre el catálogo de main de ese día fallaba en los 15 que congelaban la imagen; tras repararlos sin cambio visible con los ajustes iniciales (`bauhaus`, `cordillera_sonido`, `cubo_led`, `cubo_magico`, `curvas_fractales`, `goteo_pollock` y su transparente, `lluvia_notas` y su transparente, `medidores_vu`, `neon_lluvia`, `ola_pendulos` y su transparente, `selva_bioluminiscente` y `vitral_estalla`), los 277 visuales nativos pasan. El aviso con todos los ajustes al máximo o en una variación (más de 28 en el iPad) queda en 16 líneas de 11 visuales: `arbol_fractal` y su transparente, `cristal_electrico` (Tormenta y Brasa Viva), `espiral_dominos` y su transparente, `espiral_primos`, `fuegos_artificiales` y su transparente, `kandinsky` y `luciernagas` y su transparente. `check_native.py --strict-modifiers` sobre el catálogo completo con ASan/UBSan: 6 min 36 s en la Mac. La plantilla queda en 5 pasadas con los ajustes iniciales, no avisa al máximo ni en sus variaciones y pasa el barrido estricto. Tiempo de la revisión nativa del catálogo en la Mac, sin sanitizers: 34 s sin conteo, 50 s con el gate y 66 s con el aviso; con ASan/UBSan, `check_native.py --strict-modifiers` con la plantilla tarda 7 min 22 s. |
| Música | Contrato de 520 bytes, eventos deduplicados y conservación de historia al apagar reacción. |
| Continuidad nativa | Mismo identificador de instancia y contador de actualización después de cambiar controles, tamaño y reacción; rollback probado y nueva semilla exige reset. |
| Metal y Flutter Canvas | Los cuatro ejemplos dibujan contenido; los fondos son opacos y las partículas conservan alpha. |
| Composición gráfica | Fixture con píxeles conocidos: imágenes y samplers, alpha parcial, grupo al 50% con objetos solapados, clips anidados, huecos even-odd, suma y screen. Tolerancia de 2/255 en ambas rutas. |
| Integración productiva | Tests de adaptadores para fondos/transparencias, antiguos y nativos, mediante un catálogo aprobado simulado. No se modificó la aprobación real. |
| Admisión | Validación técnica de Liquid Chrome completada; se conserva un recibo, no una aprobación. Tests de snapshots, cambios posteriores, recursos y revocación de validez pasan. |
| Build concurrente | Generación simultánea Debug/Release/RelWithDebInfo: salidas separadas, locks y hashes coherentes. |
| Plantilla y documentación | Referencia generada desde el SDK y ejemplo compilado; guía del colaborador actualizada. |

Las pruebas Flutter de Studio sumaron 24 casos, las de estado/controlador 14 y
las de aprobación/integración 11. Los ejecutables Dart de contrato y autoría
también pasaron. El análisis de Studio y scene_compositor no reportó problemas.
CI quedó preparado; estos resultados corresponden a ejecuciones locales, no
a un workflow ya ejecutado en GitHub.

La comparación gráfica utilizó Metal real de la Mac y el motor Flutter de
pruebas. Eso no equivale a haber comparado los dos teléfonos físicos ni a
exigir identidad de píxeles entre sus GPU.

## Pendiente para cerrar la aceptación

- Instalar en el iPhone físico: falta cuenta/perfil de firma para
  `com.chic.audiovisualCreator`. El responsable indicó que no puede configurarlo
  ahora. No se cambió el bundle ni se sustituyó esa prueba por un simulador.
- Conectar un Android físico y ejecutar la composición exigente durante 15
  minutos por plataforma, registrando simulación, render, fotogramas tardíos,
  memoria, cambios de calidad y contexto térmico.
- Verificar PiP real en segundo plano, entrada/salida y continuidad de la sesión
  productiva. La conexión usa el propietario nativo existente, pero no se
  certificó su comportamiento físico en esta entrega.
- Completar el informe comparable de coste sostenido para escenas con varias
  capas dentro de la app productiva y revisar su movimiento en hardware.

El simulador verificado pertenece a esta tarea: Mac local, Device Hub,
iPhone Air / iOS 27, UUID `5FACA788-7B49-41A9-920F-A350FCA62095`, bundle
`com.chic.audiovisualCreator`. Se conservaron los ajustes del dispositivo.
Mobile MCP no pudo inicializar su agente con el Xcode instalado; lanzamiento y
capturas se verificaron mediante devicectl sobre ese mismo UUID.

Los scripts reproducibles y sus dependencias están en
`.github/workflows/check.yml`, `packages/scene_program_native/test/` y
`packages/scene_compositor/ios/Tests/`. El fixture de composición vive en
`studio/test/fixtures/native_composition`; CI lo instala sólo en su checkout
desechable, no en el catálogo que usa Franco.
