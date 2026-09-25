> Para: comprobar imágenes, samplers, grupos, recortes y mezclas. Sólo se instala en el checkout desechable de CI.

Los dos programas de prueba comparan `pixels.json`: imagen y sampler con cuatro
cuadrantes, dos rectángulos solapados dentro de un grupo al 50%, doble recorte
y hueco even-odd, mezcla aditiva y screen. Los colores interiores se aceptan
con tolerancia de dos unidades; no depende de antialiasing de los bordes.
