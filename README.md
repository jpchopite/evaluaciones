# Parcial · Diplomado en Petróleo y Gas (UCAB)

Plataforma web para aplicar el parcial: sitio estático (GitHub Pages) + base de datos y lógica en Supabase.

- **Banco de preguntas** con dificultad 1–5; la dificultad es también la ponderación (una pregunta de nivel 5 vale 5 puntos).
- **50 preguntas al azar por estudiante** (configurable), estratificadas: 10 de cada nivel, así todos tienen el mismo puntaje máximo y el parcial es comparable. Además las opciones de cada pregunta se barajan por estudiante, para que copiar «la B» no sirva.
- **Duración de 2 horas** (configurable) controlada por el servidor: el reloj del navegador es solo informativo. Al vencer, el examen se cierra y lo no respondido cuenta 0.
- **Algoritmo adaptivo:** ver abajo.
- **Nota sobre 20** = puntos obtenidos / puntos máximos × 20.

## Algoritmo adaptivo

Cada estudiante tiene un *nivel* (1–5) que empieza en **1**.

1. Se presenta la pregunta aún no vista cuya dificultad sea **la más cercana al nivel actual** (empates al azar).
2. Si **acierta**, el nivel sube 1; si **falla**, baja 1 (siempre dentro de 1–5).
3. Se repite hasta responder las 50 preguntas o agotarse el tiempo.

El resultado: quien acierta va escalando de fáciles a difíciles; un error lo devuelve a preguntas más sencillas, y vuelve a subir si acierta. Como el pool ya está fijado y balanceado, **todas las preguntas del pool se responden**; el algoritmo decide el *orden*. Nunca se le dice al estudiante si acertó ni su nivel.

La lógica vive en Postgres (`supabase/migrations/001_parcial.sql`, función `parcial._estado`). El navegador nunca recibe la respuesta correcta.

## Uso

**Estudiantes:** abren `index.html`, ingresan con cédula y código personal.

**Profesor:** abre `admin.html` con la clave de administrador. El panel tiene cinco secciones:

- **Panel de control:** indicadores en vivo (inscritos, en curso, finalizados, promedio, aprobados, duración), quién está respondiendo con su tiempo restante, distribución de notas, aciertos por nivel y por tema, y preguntas que conviene revisar.
- **Estudiantes:** búsqueda, filtros y orden; códigos con un clic para copiar; acciones por estudiante (agregar tiempo, cerrar y calificar, nuevo código, reiniciar intento, quitar). Al hacer clic en un estudiante se abre su detalle: recorrido adaptativo (gráfico de nivel pregunta a pregunta), aciertos por nivel y cada respuesta con la opción elegida y la correcta.
- **Análisis de resultados:** por pregunta, % de acierto, tiempo mediano, índice de discriminación, distractor más elegido y alertas automáticas (p. ej. «un distractor supera a la correcta», señal de clave equivocada). Exporta el análisis o todas las respuestas a CSV.
- **Banco de preguntas:** cobertura por nivel, carga de CSV arrastrando el archivo, activar o desactivar preguntas.
- **Ajustes:** duración, preguntas por estudiante, enlace para estudiantes y cambio de clave.

1. *Ajustes* → cambia la clave de administrador.
2. *Banco de preguntas* → sube el CSV (ver `plantilla_preguntas.csv`: `tema; enunciado; opcion_a…d; correcta; dificultad`). Conviene tener **al menos 10 por nivel** (≥ 50 en total) para que cada estudiante reciba 10 por nivel.
3. *Estudiantes* → pega `cédula, nombre` (puedes copiar desde Excel). Se genera un código por estudiante.
4. *Resultados* → ahí están los códigos para entregar, el avance en vivo y la exportación a CSV. «Reiniciar» anula el intento de un estudiante (queda registrado) para que pueda empezar de nuevo.

> El banco actual contiene **30 preguntas de ejemplo** (6 por nivel). Cárgalo con tus 200 usando «Reemplazar el banco actual».

## Publicar en GitHub Pages

Settings → Pages → *Deploy from a branch* → rama `main`, carpeta `/ (root)`.

## Seguridad

- Las tablas están en el esquema `parcial`, no expuesto por la API, con RLS activado y sin permisos para `anon`.
- Todo acceso es mediante funciones `parcial_*`; las de estudiante exigen el token de su examen, las de profesor la clave de administrador (guardada con hash bcrypt).
- Cinco intentos fallidos de código bloquean la cédula 5 minutos.
- La clave `sb_publishable_…` de `assets/config.js` es pública por diseño.
- Limitación inherente a un examen web sin supervisión: no se puede impedir que un estudiante use otro dispositivo o busque respuestas; el azar por estudiante y el orden adaptivo reducen la utilidad de compartir respuestas, no la eliminan.
