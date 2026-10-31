# Parcial · Diplomado en Petróleo y Gas (UCAB)

Plataforma web para aplicar el parcial: sitio estático (GitHub Pages) + base de datos y lógica en Supabase.

- **Banco de preguntas** con dificultad 1–5; la dificultad es también la ponderación (una pregunta de nivel 5 vale 5 puntos).
- **50 preguntas por estudiante** (configurable), sacadas una a una al azar de **todo el banco** según su nivel. Además las opciones de cada pregunta se barajan por estudiante, para que copiar «la B» no sirva.
- **Duración de 2 horas** (configurable) controlada por el servidor: el reloj del navegador es solo informativo. Al vencer, el examen se cierra y lo no respondido cuenta 0.
- **Algoritmo adaptivo:** ver abajo.
- **Nota sobre 20** para todos, con la misma escala: puntos obtenidos / puntaje de un recorrido perfecto × 20.

## Algoritmo adaptivo

Cada estudiante tiene un *nivel* (1–5) que empieza en **1**.

1. Se saca **al azar, de todo el banco activo**, una pregunta del nivel actual que el estudiante aún no haya visto.
2. Si **acierta**, el nivel sube 1 (N1 → N2 → … → N5; en N5 se queda mientras acierte). Si **falla**, baja 1 (nunca por debajo de N1).
3. Se repite hasta responder las 50 preguntas o agotarse el tiempo.

**Puntos y nota.** Cada acierto vale su nivel (N1 = 1 … N5 = 5). El puntaje máximo es el de un recorrido perfecto: 1+2+3+4+5+5+… (con 50 preguntas, **240**). Es el mismo para todos, así que la nota es comparable: quien acierta todo saca 20, y fallar no reduce el máximo (solo hace perder los puntos de esa pregunta y baja el nivel de la siguiente).

Si un nivel se queda sin preguntas no vistas, se usa la del nivel más cercano y se acredita el nivel del estudiante, para que no pierda puntos por un banco corto. Conviene tener **al menos 25 preguntas por nivel** (con 50 preguntas por examen).

Nunca se le dice al estudiante si acertó, ni su nivel, ni su nota: al terminar solo ve la confirmación de entrega; los resultados son solo para el profesor.

La lógica vive en Postgres (`supabase/migrations/005_banco_adaptativo.sql`, funciones `parcial._estado` y `parcial._siguiente`). El navegador nunca recibe la respuesta correcta.

## Uso

**Estudiantes:** abren `index.html`, ingresan con cédula y código personal.

**Profesor:** abre `admin.html` con la clave de administrador. El panel tiene cinco secciones:

- **Panel de control:** indicadores en vivo (inscritos, en curso, finalizados, promedio, aprobados, duración), quién está respondiendo con su tiempo restante, distribución de notas, aciertos por nivel y por tema, y preguntas que conviene revisar.
- **Estudiantes:** búsqueda, filtros y orden; códigos con un clic para copiar; acciones por estudiante (agregar tiempo, cerrar y calificar, nuevo código, reiniciar intento, quitar). Al hacer clic en un estudiante se abre su detalle: recorrido adaptativo (gráfico de nivel pregunta a pregunta), aciertos por nivel y cada respuesta con la opción elegida y la correcta.
- **Análisis de resultados:** por pregunta, % de acierto, tiempo mediano, índice de discriminación, distractor más elegido y alertas automáticas (p. ej. «un distractor supera a la correcta», señal de clave equivocada). Exporta el análisis o todas las respuestas a CSV.
- **Banco de preguntas:** cobertura por nivel, carga de CSV arrastrando el archivo, activar o desactivar preguntas.
- **Ajustes:** duración, preguntas por estudiante, enlace para estudiantes y cambio de clave.

1. *Ajustes* → cambia la clave de administrador.
2. *Banco de preguntas* → llena `plantilla_preguntas.xlsx` (tiene listas desplegables y un contador por nivel), guárdala como CSV y súbela; o sube el CSV (ver `plantilla_preguntas.csv`: `tema; enunciado; opcion_a…d; correcta; dificultad`). Conviene tener **al menos 25 por nivel**.
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
