-- Archivo de parciales: guarda las estadísticas de un parcial terminado para consultarlas
-- después en el panel (sección «Parcial anterior»), aunque se borren los estudiantes y se
-- cambie el banco de preguntas.
--
-- 1. Las consultas de resultados, análisis y respuestas pasan a funciones internas
--    (parcial._resultados, _analisis, _respuestas); los RPC del panel las llaman tras
--    comprobar la clave. Su resultado no cambia.
-- 2. parcial.archivos guarda una copia congelada (jsonb) de esas tres consultas.
-- 3. RPC con clave: parcial_admin_archivos (lista) y parcial_admin_archivo (uno).

create or replace function parcial._resultados() returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'id', s.id, 'cedula', s.cedula, 'nombre', s.nombre, 'codigo', s.codigo,
        'estado', coalesce(e.estado, 'sin_iniciar'), 'motivo', e.motivo_fin,
        'respondidas', c.resp, 'correctas', c.ok, 'total', e.n_preguntas,
        'puntos', e.puntos_obtenidos, 'puntos_max', e.puntaje_max, 'nota', e.puntaje,
        'nivel', e.nivel, 'termina_en', e.termina_en,
        'iniciado_en', e.iniciado_en, 'finalizado_en', e.finalizado_en)
        || coalesce(case when e.id is not null then parcial._resumen_eventos(e.id) end, '{}'::jsonb)
      order by s.nombre)
    from parcial.estudiantes s
    left join parcial.examenes e on e.estudiante_id = s.id and not e.anulado
    left join lateral (
      select count(*) filter (where respondida_en is not null) resp,
             count(*) filter (where es_correcta) ok
        from parcial.examen_preguntas where examen_id = e.id) c on true
    where s.activo
  ), '[]'::jsonb);
end $$;

create or replace function public.parcial_admin_resultados(p_clave text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  return parcial._resultados();
end $$;

create or replace function parcial._analisis() returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare r jsonb;
begin
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

create or replace function public.parcial_admin_analisis(p_clave text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  return parcial._analisis();
end $$;

create or replace function parcial._respuestas() returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
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

create or replace function public.parcial_admin_respuestas(p_clave text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  return parcial._respuestas();
end $$;

create table if not exists parcial.archivos (
  id int generated always as identity primary key,
  titulo text not null,
  creado_en timestamptz not null default now(),
  config jsonb not null default '{}',
  resultados jsonb not null,
  analisis jsonb not null,
  respuestas jsonb not null
);
alter table parcial.archivos enable row level security;
revoke all on parcial.archivos from public, anon, authenticated;

-- Copia el parcial actual al archivo. El análisis guarda solo las preguntas que se presentaron.
create or replace function parcial._archivar(p_titulo text) returns int
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare v_an jsonb := parcial._analisis(); v_id int;
begin
  v_an := jsonb_set(v_an, '{por_pregunta}', coalesce((
    select jsonb_agg(q) from jsonb_array_elements(v_an -> 'por_pregunta') q where (q ->> 'n')::int > 0), '[]'));
  insert into parcial.archivos (titulo, config, resultados, analisis, respuestas)
  values (p_titulo,
          (select jsonb_object_agg(clave, valor) from parcial.config where clave <> 'admin_hash'),
          parcial._resultados(), v_an, parcial._respuestas())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.parcial_admin_archivos(p_clave text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'titulo', titulo, 'creado_en', creado_en,
      'estudiantes', jsonb_array_length(resultados),
      'finalizados', (analisis -> 'resumen' ->> 'finalizados')::int) order by creado_en desc)
    from parcial.archivos), '[]'::jsonb);
end $$;

create or replace function public.parcial_admin_archivo(p_clave text, p_id int) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare r jsonb;
begin
  perform parcial._admin(p_clave);
  select jsonb_build_object('id', id, 'titulo', titulo, 'creado_en', creado_en, 'config', config,
                            'resultados', resultados, 'analisis', analisis, 'respuestas', respuestas)
    into r from parcial.archivos where id = p_id;
  if r is null then raise exception 'Archivo no encontrado'; end if;
  return r;
end $$;

revoke all on function parcial._resultados(), parcial._analisis(), parcial._respuestas(),
  parcial._archivar(text) from public, anon, authenticated;
revoke all on function public.parcial_admin_archivos(text), public.parcial_admin_archivo(text, int) from public;
grant execute on function public.parcial_admin_archivos(text), public.parcial_admin_archivo(text, int) to anon, authenticated;
