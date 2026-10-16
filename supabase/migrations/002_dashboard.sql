-- Dashboard del profesor: detalle por estudiante, análisis de preguntas y acciones de control.
-- Convención: ningún DELETE; los registros se anulan/desactivan para conservar el rastro.

-- Resultados con datos extra para el seguimiento en vivo
create or replace function public.parcial_admin_resultados(p_clave text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'id', s.id, 'cedula', s.cedula, 'nombre', s.nombre, 'codigo', s.codigo,
        'estado', coalesce(e.estado, 'sin_iniciar'), 'motivo', e.motivo_fin,
        'respondidas', c.resp, 'correctas', c.ok, 'total', c.tot,
        'puntos', e.puntos_obtenidos, 'puntos_max', e.puntaje_max, 'nota', e.puntaje,
        'nivel', e.nivel, 'termina_en', e.termina_en,
        'iniciado_en', e.iniciado_en, 'finalizado_en', e.finalizado_en)
      order by s.nombre)
    from parcial.estudiantes s
    left join parcial.examenes e on e.estudiante_id = s.id and not e.anulado
    left join lateral (
      select count(*) filter (where respondida_en is not null) resp,
             count(*) filter (where es_correcta) ok,
             count(*) tot
        from parcial.examen_preguntas where examen_id = e.id) c on true
    where s.activo
  ), '[]'::jsonb);
end $$;

-- Detalle de un estudiante: cada pregunta en el orden en que se le presentó
create function public.parcial_admin_detalle(p_clave text, p_estudiante_id int) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare s parcial.estudiantes%rowtype; e parcial.examenes%rowtype; v_anul int;
begin
  perform parcial._admin(p_clave);
  select * into s from parcial.estudiantes where id = p_estudiante_id;
  if not found then raise exception 'Estudiante no encontrado'; end if;
  select * into e from parcial.examenes where estudiante_id = s.id and not anulado;
  select count(*) into v_anul from parcial.examenes where estudiante_id = s.id and anulado;
  return jsonb_build_object(
    'estudiante', jsonb_build_object('id', s.id, 'cedula', s.cedula, 'nombre', s.nombre, 'codigo', s.codigo),
    'intentos_anulados', v_anul,
    'examen', case when e.id is null then null else jsonb_build_object(
        'estado', e.estado, 'motivo', e.motivo_fin, 'iniciado_en', e.iniciado_en,
        'termina_en', e.termina_en, 'finalizado_en', e.finalizado_en, 'nota', e.puntaje,
        'puntos', e.puntos_obtenidos, 'puntos_max', e.puntaje_max, 'nivel', e.nivel) end,
    'respuestas', case when e.id is null then '[]'::jsonb else coalesce((
        select jsonb_agg(jsonb_build_object(
            'orden', ep.orden_presentacion, 'pregunta_id', p.id, 'tema', p.tema,
            'enunciado', p.enunciado, 'dificultad', p.dificultad, 'nivel', ep.nivel_al_presentar,
            'respondida', ep.respondida_en is not null,
            'elegida', case when ep.opcion_elegida is null then null
                            else p.opciones ->> (ep.orden_opciones[ep.opcion_elegida + 1])::int end,
            'correcta_txt', p.opciones ->> p.correcta::int,
            'es_correcta', ep.es_correcta, 'puntos', ep.puntos,
            'segundos', round(extract(epoch from ep.respondida_en - ep.presentada_en)::numeric, 0))
          order by ep.orden_presentacion nulls last, ep.id)
          from parcial.examen_preguntas ep
          join parcial.preguntas p on p.id = ep.pregunta_id
         where ep.examen_id = e.id), '[]'::jsonb) end);
end $$;

-- Análisis global del parcial
create function public.parcial_admin_analisis(p_clave text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare r jsonb;
begin
  perform parcial._admin(p_clave);
  with ex as (
    select e.id, e.estado, e.puntaje, e.iniciado_en, e.finalizado_en
      from parcial.examenes e join parcial.estudiantes s on s.id = e.estudiante_id
     where not e.anulado and s.activo
  ),
  resp as (
    select ep.pregunta_id, ep.es_correcta, ep.orden_opciones, ep.opcion_elegida,
           extract(epoch from ep.respondida_en - ep.presentada_en) seg,
           p.dificultad, coalesce(p.tema, 'Sin tema') tema, ex.puntaje
      from parcial.examen_preguntas ep
      join ex on ex.id = ep.examen_id
      join parcial.preguntas p on p.id = ep.pregunta_id
     where ep.respondida_en is not null
  ),
  mal_cnt as (
    select pregunta_id, orden_opciones[opcion_elegida + 1] idx, count(*) n
      from resp where not es_correcta group by 1, 2
  ),
  mal as (
    select distinct on (pregunta_id) pregunta_id, idx, n from mal_cnt order by pregunta_id, n desc
  )
  select jsonb_build_object(
    'resumen', (select jsonb_build_object(
        'finalizados', count(*), 'promedio', round(avg(puntaje), 2),
        'mediana', round((percentile_cont(0.5) within group (order by puntaje))::numeric, 2),
        'min', min(puntaje), 'max', max(puntaje),
        'desv', round(stddev_pop(puntaje)::numeric, 2),
        'aprobados', count(*) filter (where puntaje >= 10),
        'minutos_med', round((percentile_cont(0.5) within group
            (order by extract(epoch from finalizado_en - iniciado_en) / 60))::numeric, 0))
      from ex where estado = 'finalizado'),
    'distribucion', (select jsonb_agg(c order by b)
      from (select b, count(ex.id) c from generate_series(0, 9) b
              left join ex on ex.estado = 'finalizado' and least(floor(ex.puntaje / 2), 9) = b
             group by b) d),
    'por_dificultad', (select coalesce(jsonb_agg(jsonb_build_object(
        'dificultad', dificultad, 'n', n, 'aciertos', ok,
        'pct', round(100.0 * ok / n, 1), 'seg_med', seg) order by dificultad), '[]'::jsonb)
      from (select dificultad, count(*) n, count(*) filter (where es_correcta) ok,
                   round((percentile_cont(0.5) within group (order by seg))::numeric, 0) seg
              from resp group by dificultad) x),
    'por_tema', (select coalesce(jsonb_agg(jsonb_build_object(
        'tema', tema, 'n', n, 'aciertos', ok, 'pct', round(100.0 * ok / n, 1)) order by tema), '[]'::jsonb)
      from (select tema, count(*) n, count(*) filter (where es_correcta) ok
              from resp group by tema) x),
    'por_pregunta', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'tema', p.tema, 'enunciado', p.enunciado, 'opciones', p.opciones,
        'correcta', p.correcta, 'dificultad', p.dificultad, 'activa', p.activa,
        'n', coalesce(s.n, 0), 'aciertos', coalesce(s.ok, 0),
        'pct', case when s.n > 0 then round(100.0 * s.ok / s.n, 1) end,
        'seg_med', s.seg_med, 'disc', s.disc,
        'distractor', case when m.idx is not null
                           then jsonb_build_object('texto', p.opciones ->> (m.idx)::int, 'n', m.n) end)
        order by p.dificultad, p.id), '[]'::jsonb)
      from parcial.preguntas p
      left join (select pregunta_id, count(*) n, count(*) filter (where es_correcta) ok,
                        round((percentile_cont(0.5) within group (order by seg))::numeric, 0) seg_med,
                        round((corr(case when es_correcta then 1.0 else 0.0 end, puntaje))::numeric, 2) disc
                   from resp group by pregunta_id) s on s.pregunta_id = p.id
      left join mal m on m.pregunta_id = p.id)
  ) into r;
  return r;
end $$;

-- Todas las respuestas en filas planas (para exportar a Excel)
create function public.parcial_admin_respuestas(p_clave text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'cedula', s.cedula, 'nombre', s.nombre, 'orden', ep.orden_presentacion,
        'tema', p.tema, 'enunciado', p.enunciado, 'dificultad', p.dificultad,
        'nivel', ep.nivel_al_presentar,
        'elegida', case when ep.opcion_elegida is null then null
                        else p.opciones ->> (ep.orden_opciones[ep.opcion_elegida + 1])::int end,
        'correcta_txt', p.opciones ->> p.correcta::int,
        'es_correcta', ep.es_correcta, 'puntos', ep.puntos,
        'segundos', round(extract(epoch from ep.respondida_en - ep.presentada_en)::numeric, 0))
      order by s.nombre, ep.orden_presentacion nulls last)
    from parcial.examen_preguntas ep
    join parcial.examenes e on e.id = ep.examen_id and not e.anulado
    join parcial.estudiantes s on s.id = e.estudiante_id and s.activo
    join parcial.preguntas p on p.id = ep.pregunta_id
   where ep.presentada_en is not null
  ), '[]'::jsonb);
end $$;

-- Acciones de control
create function public.parcial_admin_extender(p_clave text, p_estudiante_id int, p_minutos int) returns void
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  if p_minutos is null or p_minutos < 1 or p_minutos > 240 then raise exception 'Minutos inválidos (1 a 240)'; end if;
  update parcial.examenes
     set termina_en = greatest(termina_en, now()) + make_interval(mins => p_minutos)
   where estudiante_id = p_estudiante_id and not anulado and estado = 'en_curso';
  if not found then raise exception 'El estudiante no tiene un examen en curso'; end if;
end $$;

create function public.parcial_admin_forzar_entrega(p_clave text, p_estudiante_id int) returns void
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare v_ex int;
begin
  perform parcial._admin(p_clave);
  select id into v_ex from parcial.examenes
   where estudiante_id = p_estudiante_id and not anulado and estado = 'en_curso';
  if v_ex is null then raise exception 'El estudiante no tiene un examen en curso'; end if;
  perform parcial._finalizar(v_ex, 'entregado_por_profesor');
end $$;

create function public.parcial_admin_nuevo_codigo(p_clave text, p_estudiante_id int) returns text
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare v text;
begin
  perform parcial._admin(p_clave);
  select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789',
           1 + (get_byte(extensions.gen_random_bytes(1), 0) % 31), 1), '')
    into v from generate_series(1, 6);
  update parcial.estudiantes set codigo = v, fallos = 0, bloqueado_hasta = null where id = p_estudiante_id;
  if not found then raise exception 'Estudiante no encontrado'; end if;
  return v;
end $$;

create function public.parcial_admin_activar_pregunta(p_clave text, p_pregunta_id int, p_activa boolean) returns void
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  update parcial.preguntas set activa = p_activa where id = p_pregunta_id;
end $$;

-- Permisos
revoke all on function
  public.parcial_admin_detalle(text, int), public.parcial_admin_analisis(text),
  public.parcial_admin_respuestas(text), public.parcial_admin_extender(text, int, int),
  public.parcial_admin_forzar_entrega(text, int), public.parcial_admin_nuevo_codigo(text, int),
  public.parcial_admin_activar_pregunta(text, int, boolean)
  from public;
grant execute on function
  public.parcial_admin_detalle(text, int), public.parcial_admin_analisis(text),
  public.parcial_admin_respuestas(text), public.parcial_admin_extender(text, int, int),
  public.parcial_admin_forzar_entrega(text, int), public.parcial_admin_nuevo_codigo(text, int),
  public.parcial_admin_activar_pregunta(text, int, boolean)
  to anon, authenticated;
