-- Nuevo parcial (25 nov 2026): archiva el primero y prepara uno de 20 preguntas.
--
-- 1. Guarda el parcial actual en parcial.archivos («Parcial 1 · Petróleo y Gas»), una sola vez.
-- 2. Desactiva todo el banco anterior (no se borra: sus preguntas siguen ligadas al archivo).
-- 3. Carga 53 preguntas de «El modelo de Hubbert» en los 5 niveles (no duplica si se repite).
--    El segundo tema se agregará después.
-- 4. 20 preguntas por estudiante y la entrada al parcial CERRADA hasta que el profesor la abra.
--
-- No borra estudiantes ni exámenes: eso va en un script aparte, después de comprobar el archivo.
do $$
begin
  if exists (select 1 from parcial.examenes where estado = 'en_curso' and termina_en > now()) then
    raise exception 'Cancelado: hay un examen en curso';
  end if;
  -- Solo la primera vez: así, si se repite el script, no desactiva el segundo tema.
  if not exists (select 1 from parcial.archivos where titulo = 'Parcial 1 · Petróleo y Gas') then
    perform parcial._archivar('Parcial 1 · Petróleo y Gas');
    update parcial.preguntas set activa = false
     where activa and coalesce(tema, '') <> 'El modelo de Hubbert';
  end if;
end $$;

insert into parcial.preguntas (tema, enunciado, opciones, correcta, dificultad)
select 'El modelo de Hubbert', n.enunciado, n.opciones, n.correcta, n.dificultad
  from (values
-- ── Nivel 1: conceptos básicos ──
('¿Quién propuso el modelo conocido como «curva de Hubbert»?',
 jsonb_build_array('Marion King Hubbert, geofísico estadounidense', 'John D. Rockefeller, empresario petrolero', 'Edwin Drake, pionero de la perforación de pozos', 'Juan Pablo Pérez Alfonzo, ministro venezolano'), 0, 1),
('¿Qué forma tiene la curva de producción de Hubbert?',
 jsonb_build_array('Una recta que crece sin límite', 'Una campana: sube, alcanza un máximo y luego baja', 'Una línea horizontal constante', 'Una curva que solo desciende desde el inicio'), 1, 1),
('¿Qué recurso estudió principalmente Hubbert con su modelo?',
 jsonb_build_array('El agua dulce', 'La energía solar', 'El petróleo y otros combustibles fósiles', 'El oro y la plata'), 2, 1),
('En el modelo de Hubbert, ¿cómo se llama el punto de máxima producción?',
 jsonb_build_array('El pozo descubridor', 'La reserva probada', 'El punto de equilibrio', 'El pico o cénit de producción'), 3, 1),
('Según Hubbert, ¿por qué la producción de petróleo de una región termina declinando?',
 jsonb_build_array('Porque el petróleo es un recurso finito que se agota', 'Porque el petróleo se regenera muy rápido', 'Porque las leyes prohíben producir más', 'Porque los precios siempre bajan'), 0, 1),
('¿En qué década presentó Hubbert su famosa predicción sobre el petróleo de Estados Unidos?',
 jsonb_build_array('En la de 1920', 'En la de 1950', 'En la de 1980', 'En la de 2000'), 1, 1),
('¿Qué país fue el objeto de la predicción más conocida de Hubbert?',
 jsonb_build_array('Venezuela', 'Arabia Saudita', 'Estados Unidos', 'Rusia'), 2, 1),
('¿Qué se conoce como «pico del petróleo» (peak oil)?',
 jsonb_build_array('El precio más alto del barril en la historia', 'La profundidad máxima que alcanza un pozo', 'El año en que se descubrió el primer yacimiento', 'El momento en que la producción de petróleo llega a su máximo y empieza a declinar'), 3, 1),
-- ── Nivel 2: elementos del modelo ──
('Según Hubbert, ¿cuándo alcanza su máximo la producción de una región?',
 jsonb_build_array('Cuando se ha extraído aproximadamente la mitad del petróleo recuperable', 'Apenas se descubre el primer yacimiento', 'Cuando ya se agotó todo el petróleo', 'Cuando se ha extraído el 10 % del petróleo recuperable'), 0, 2),
('¿Qué representa el área bajo la curva de Hubbert?',
 jsonb_build_array('El dinero total obtenido por la venta del petróleo', 'La cantidad total de petróleo que se puede recuperar en la región', 'El número de pozos perforados', 'Las ganancias de las empresas operadoras'), 1, 2),
('Hubbert predijo que la producción de los 48 estados contiguos de EE. UU. llegaría a su máximo…',
 jsonb_build_array('Hacia el año 1900', 'Después del año 2050', 'Entre 1965 y 1970', 'Nunca: creía que crecería siempre'), 2, 2),
('¿En qué año alcanzó la producción de petróleo de EE. UU. el máximo que Hubbert había anticipado?',
 jsonb_build_array('1956', '1985', '2000', '1970'), 3, 2),
('¿Qué muestra la parte ascendente (izquierda) de la curva de Hubbert?',
 jsonb_build_array('La etapa de crecimiento, en la que se descubren y desarrollan nuevos yacimientos', 'La etapa de agotamiento de los yacimientos', 'El cierre progresivo de los pozos', 'La caída de los precios del petróleo'), 0, 2),
('En el modelo clásico de Hubbert, ¿cómo es la caída después del pico comparada con la subida?',
 jsonb_build_array('Mucho más rápida, casi inmediata', 'Aproximadamente simétrica a la subida', 'No hay caída después del pico', 'Siempre más lenta y sin final'), 1, 2),
('Según Hubbert, ¿qué ocurre antes del pico de producción de una región?',
 jsonb_build_array('El pico del precio del petróleo', 'El agotamiento total de las reservas', 'El pico de descubrimientos de nuevos yacimientos', 'La nacionalización de la industria'), 2, 2),
('Al aplicar el modelo de Hubbert se habla de la URR. ¿Qué es?',
 jsonb_build_array('Una unidad de refinación regional', 'El uso racional de los recursos', 'La renta petrolera del Estado', 'Los recursos últimos recuperables: todo el petróleo que llegará a extraerse en la región'), 3, 2),
('En una gráfica de la curva de Hubbert, ¿qué se representa en cada eje?',
 jsonb_build_array('Tiempo en el eje horizontal y producción anual en el vertical', 'Precio en el horizontal y demanda en el vertical', 'Profundidad en el horizontal y presión en el vertical', 'Número de pozos en el horizontal y costo en el vertical'), 0, 2),
-- ── Nivel 3: interpretación ──
('Si los recursos recuperables (URR) de una región son 200.000 millones de barriles, ¿cuánto se habrá producido aproximadamente al llegar al pico?',
 jsonb_build_array('50.000 millones de barriles', '100.000 millones de barriles', '150.000 millones de barriles', '200.000 millones de barriles'), 1, 3),
('Una región ha producido 30.000 de sus 100.000 millones de barriles recuperables. Según Hubbert, ¿en qué etapa está?',
 jsonb_build_array('Ya pasó el pico y está en declinación', 'Está exactamente en el pico', 'Todavía antes del pico, en la fase de crecimiento', 'Ya agotó su petróleo'), 2, 3),
('¿Cuál es la principal crítica económica al modelo de Hubbert?',
 jsonb_build_array('Que solo sirve para el carbón', 'Que exige conocer el precio exacto del barril', 'Que se basa en encuestas a las empresas', 'Que no considera precios, tecnología ni regulación, que pueden cambiar la producción'), 3, 3),
('A finales de la década de 2010 la producción de EE. UU. superó su máximo de 1970. ¿Qué lo explica principalmente?',
 jsonb_build_array('El petróleo de lutitas (esquisto), gracias a la fractura hidráulica y la perforación horizontal', 'El descubrimiento de grandes yacimientos en Nueva York', 'La prohibición de importar petróleo', 'Un error en las cifras de producción de 1970'), 0, 3),
('¿Por qué la producción de un país puede apartarse de la curva suave de Hubbert?',
 jsonb_build_array('Porque el petróleo cambia de volumen con el paso del tiempo', 'Por decisiones políticas y económicas, como cuotas de la OPEP, nacionalizaciones o sanciones', 'Porque la curva solo vale para un único pozo', 'Porque la producción no se puede medir'), 1, 3),
('Un país descubrió la mayor parte de su petróleo hace 40 años y desde entonces casi no hay hallazgos nuevos. ¿Qué anticipa el modelo de Hubbert?',
 jsonb_build_array('Que su producción crecerá sin límite', 'Que el precio del petróleo bajará a cero', 'Que su producción ya alcanzó o pronto alcanzará el pico, y luego declinará', 'Que sus reservas se repondrán solas'), 2, 3),
('¿Qué supuesto del modelo resulta más discutible en países con grandes reservas, como Venezuela?',
 jsonb_build_array('Que el petróleo existe', 'Que la producción se mide en barriles', 'Que el petróleo es un recurso finito', 'Que la producción depende sobre todo de la geología, y no de la inversión ni de las decisiones del Estado'), 3, 3),
('La curva de producción de una región muestra dos picos separados. ¿Qué suele explicarlo?',
 jsonb_build_array('La llegada de una nueva tecnología o de nuevas zonas de producción, que inicia un segundo ciclo', 'Un error de medición', 'Que el petróleo se regeneró', 'Que la región cambió de nombre'), 0, 3),
('¿En qué se diferencian las «reservas probadas» de los «recursos últimos recuperables» (URR)?',
 jsonb_build_array('Son exactamente lo mismo', 'La URR suma lo ya producido, las reservas y lo que falta por descubrir; las reservas probadas son solo lo demostrado que queda por extraer', 'Las reservas probadas incluyen todo lo ya producido', 'La URR solo cuenta el petróleo ya vendido'), 1, 3),
('Según el modelo de Hubbert, ¿qué ocurre con la producción después del pico, aunque la demanda siga creciendo?',
 jsonb_build_array('Crece al mismo ritmo que la demanda', 'Se mantiene constante para siempre', 'Declina, porque cada vez queda menos petróleo por extraer', 'Se duplica'), 2, 3),
-- ── Nivel 4: análisis y cálculos sencillos ──
('Una región empezó a producir en 1930 y alcanzó su pico en 1980. Si la curva es simétrica, ¿hacia qué año quedaría prácticamente agotada?',
 jsonb_build_array('1990', '2000', '2080', '2030'), 3, 4),
('En el modelo de Hubbert la producción máxima es P = a × URR / 4. Si a = 0,06 por año y la URR es de 200.000 millones de barriles, ¿cuál es la producción máxima?',
 jsonb_build_array('3.000 millones de barriles por año', '12.000 millones de barriles por año', '800 millones de barriles por año', '50.000 millones de barriles por año'), 0, 4),
('Una región tiene una URR de 120.000 millones de barriles y ya produjo 90.000 millones. ¿Cuánto le queda y en qué fase está?',
 jsonb_build_array('30.000 millones; antes del pico', '30.000 millones; después del pico, en declinación', '90.000 millones; en el pico', '60.000 millones; en el pico'), 1, 4),
('En 1956 Hubbert estimó entre 150.000 y 200.000 millones de barriles recuperables en EE. UU. y ubicó el pico entre 1965 y 1970. ¿Por qué daba dos fechas?',
 jsonb_build_array('Porque no estaba seguro del año en curso', 'Porque se refería a dos países distintos', 'Porque cada estimación de la URR da un pico distinto: más petróleo recuperable lo retrasa', 'Porque esperaba dos picos sucesivos'), 2, 4),
('En la «linealización de Hubbert» se grafica P/Q (producción anual entre producción acumulada) contra Q. ¿Qué indica el punto donde la recta corta el eje horizontal?',
 jsonb_build_array('El año del pico', 'La producción máxima anual', 'La tasa de crecimiento', 'La URR: el total de petróleo recuperable'), 3, 4),
('Un país produce 10 millones de barriles diarios. ¿Cuánto produce aproximadamente en un año?',
 jsonb_build_array('3.650 millones de barriles', '365 millones de barriles', '10.000 millones de barriles', '36.500 millones de barriles'), 0, 4),
('En EE. UU. los descubrimientos alcanzaron su máximo hacia la década de 1930 y la producción en 1970. Si en otro país los descubrimientos llegaron a su máximo en 1975, con un desfase parecido, ¿cuándo esperarías su pico de producción?',
 jsonb_build_array('Hacia 1980', 'Hacia 2015', 'Hacia 1950', 'Hacia 2100'), 1, 4),
('Dos países tienen la misma URR, pero uno extrae su petróleo mucho más rápido. Según el modelo, ¿qué le pasa al más rápido?',
 jsonb_build_array('Tiene un pico más bajo y más tardío', 'Su curva es idéntica a la del otro', 'Tiene un pico más alto y más temprano, y declina antes', 'Nunca llega a un pico'), 2, 4),
('¿Por qué el modelo de Hubbert funciona mejor para una región grande que para un solo yacimiento?',
 jsonb_build_array('Porque un yacimiento aislado no produce petróleo', 'Porque los yacimientos grandes están prohibidos', 'Porque en un yacimiento la curva siempre es una recta', 'Porque al sumar muchos yacimientos sus variaciones se compensan y la producción total se parece a una campana'), 3, 4),
('Un perito usa la curva de Hubbert para sostener ante un tribunal cuántos años de producción le quedan a una concesión. ¿Cuál es la debilidad más fuerte de ese argumento?',
 jsonb_build_array('Que la URR estimada puede cambiar con nueva tecnología, otros precios o nuevos descubrimientos', 'Que la curva no tiene unidades', 'Que Hubbert era geofísico y no abogado', 'Que la curva es demasiado antigua para usarse en juicio'), 0, 4),
-- ── Nivel 5: cálculos de varios pasos y análisis crítico ──
('En una linealización de Hubbert la recta es P/Q = 0,08 − 0,0004 × Q (Q en miles de millones de barriles). ¿Cuál es la URR?',
 jsonb_build_array('80 mil millones de barriles', '200 mil millones de barriles', '320 mil millones de barriles', '0,08 mil millones de barriles'), 1, 5),
('Con la recta P/Q = 0,08 − 0,0004 × Q (Q en miles de millones de barriles), ¿cuál es la producción máxima, P = a × URR / 4?',
 jsonb_build_array('16 mil millones de barriles por año', '8 mil millones de barriles por año', '4 mil millones de barriles por año', '2 mil millones de barriles por año'), 2, 5),
('Según el modelo, P = a × Q × (1 − Q / URR). Con a = 0,1 por año, URR = 200 y Q = 50 (en miles de millones de barriles), ¿cuál es la producción anual?',
 jsonb_build_array('5 mil millones de barriles', '2,5 mil millones de barriles', '10 mil millones de barriles', '3,75 mil millones de barriles'), 3, 5),
('En su pico una región produce 4.000 millones de barriles por año y su tasa es a = 0,05 por año. Con P = a × URR / 4, ¿cuál es su URR?',
 jsonb_build_array('320.000 millones de barriles', '80.000 millones de barriles', '200.000 millones de barriles', '20.000 millones de barriles'), 0, 5),
('Si la producción acumulada en el pico fue de 75.000 millones de barriles, ¿cuál es la URR estimada y cuánto falta por producir?',
 jsonb_build_array('75.000 millones; no falta nada', '150.000 millones; faltan 75.000 millones', '300.000 millones; faltan 225.000 millones', '112.500 millones; faltan 37.500 millones'), 1, 5),
('Hubbert ubicó el pico de EE. UU. hacia 1970 con una URR de 200.000 millones de barriles. Si la URR hubiera sido de 300.000 millones con la misma tasa de crecimiento, ¿qué habría pasado con el pico?',
 jsonb_build_array('Habría llegado antes y sería más bajo', 'No habría cambiado', 'Habría llegado después y sería más alto', 'No habría pico'), 2, 5),
('La recta de linealización de un país corta el eje vertical en 0,05 y el horizontal en 180.000 millones de barriles. ¿Cuál es su producción máxima?',
 jsonb_build_array('9.000 millones de barriles por año', '4.500 millones de barriles por año', '3.600 millones de barriles por año', '2.250 millones de barriles por año'), 3, 5),
('Un país tiene una URR estimada de 100.000 millones de barriles, ya produjo 50.000 millones y su producción anual sigue creciendo. ¿Qué conclusión es más razonable?',
 jsonb_build_array('La URR probablemente está subestimada, o la producción no sigue una curva simétrica', 'El modelo prueba que la producción crecerá para siempre', 'El país ya agotó su petróleo', 'La producción anual no guarda relación con la URR'), 0, 5),
('¿Por qué un precio del petróleo más alto puede retrasar el pico de producción de una región?',
 jsonb_build_array('Porque con precios altos el petróleo se forma más rápido', 'Porque vuelve rentable extraer petróleo más costoso, lo que aumenta el petróleo económicamente recuperable', 'Porque reduce la demanda a cero', 'Porque obliga a cerrar pozos'), 1, 5),
('En su pico una región produce 2,9 millones de barriles diarios y su tasa es a = 0,06 por año. Con P = a × URR / 4, ¿cuál es aproximadamente su URR?',
 jsonb_build_array('17.600 millones de barriles', '193.000 millones de barriles', '70.600 millones de barriles', '4.200 millones de barriles'), 2, 5),
('Un analista hace la linealización de Hubbert solo con los primeros años de producción, cuando los puntos aún no forman una recta estable. ¿Cuál es el riesgo?',
 jsonb_build_array('Ninguno: la recta siempre es exacta', 'Que la tasa de crecimiento salga igual a cero', 'Que el pico ya haya ocurrido sin saberlo', 'Que la URR estimada sea muy inexacta, porque al inicio los puntos se desvían de la recta'), 3, 5),
('Hubbert también estimó que la producción mundial tendría su pico hacia el año 2000. ¿Qué hecho contradice más directamente esa predicción?',
 jsonb_build_array('Que la producción mundial siguió creciendo en las décadas de 2000 y 2010, con aportes del petróleo no convencional', 'Que EE. UU. tuvo su pico en 1970', 'Que la producción del Mar del Norte declinó', 'Que el petróleo es un recurso finito'), 0, 5),
('¿Por qué la producción de un país sujeto a cuotas de la OPEP suele ser mala candidata para ajustar el modelo de Hubbert?',
 jsonb_build_array('Porque la OPEP no publica datos de producción', 'Porque su producción la limitan decisiones políticas y no solo la geología, así que la curva no refleja el agotamiento', 'Porque esos países no tienen petróleo', 'Porque sus pozos son más profundos'), 1, 5),
('En el modelo logístico la producción acumulada es Q(t) = URR / (1 + e^(−a × (t − tm))). ¿Qué representa tm?',
 jsonb_build_array('El año del primer descubrimiento', 'El año en que se agota el petróleo', 'El año del pico de producción, cuando Q = URR / 2', 'La tasa de crecimiento de la producción'), 2, 5),
('Una región tiene una URR de 60.000 millones de barriles y a = 0,1 por año. Si desde el pico mantuviera constante su producción máxima (P = a × URR / 4), ¿en cuántos años extraería lo que le queda?',
 jsonb_build_array('10 años', '40 años', '5 años', '20 años'), 3, 5),
('¿Qué conclusión de política pública es la más prudente a partir del modelo de Hubbert?',
 jsonb_build_array('Que la producción de un recurso finito acabará declinando, por lo que conviene planificar los ingresos fiscales y la transición, revisando las estimaciones con datos nuevos', 'Que el Estado debe prohibir la producción después del pico', 'Que el precio del petróleo bajará siempre después del pico', 'Que los contratos petroleros deben durar exactamente hasta el pico'), 0, 5)
) as n(enunciado, opciones, correcta, dificultad)
 where not exists (select 1 from parcial.preguntas p where p.enunciado = n.enunciado);

insert into parcial.config (clave, valor) values ('n_preguntas', '20'), ('entrada_abierta', 'false')
on conflict (clave) do update set valor = excluded.valor;

select dificultad, count(*) activas from parcial.preguntas where activa group by 1 order by 1;
