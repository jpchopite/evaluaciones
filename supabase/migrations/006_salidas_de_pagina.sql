-- Registro de salidas de la página del parcial (control antitrampa).
--
-- La página del estudiante avisa al servidor cuando:
--   · salio  → cambia de pestaña, minimiza, cambia de aplicación o pasa a otra ventana
--              (motivo: 'pestana', 'ventana' o 'cerro' si cerró o recargó la página);
--   · volvio → regresa a la página (el servidor calcula cuánto estuvo fuera);
--   · copio  → copia texto de la pregunta.
-- La hora la pone el servidor. Solo se registra mientras el examen está en curso.
-- El profesor ve el conteo en la lista de estudiantes y la cronología en el detalle.

create table if not exists parcial.eventos (
  id bigint generated always as identity primary key,
  examen_id int not null references parcial.examenes (id) on delete cascade,
  tipo text not null check (tipo in ('salio', 'volvio', 'copio')),
  motivo text,
  pregunta_n int,            -- número de la pregunta que tenía en pantalla
  segundos int,              -- en 'volvio': cuánto estuvo fuera
  en timestamptz not null default now()
);
create index if not exists eventos_examen on parcial.eventos (examen_id, id);
alter table parcial.eventos enable row level security;
revoke all on parcial.eventos from public, anon, authenticated;

create or replace function public.parcial_evento(p_token uuid, p_tipo text, p_motivo text default null)
returns void
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare
  v_ex int := parcial._ex_por_token(p_token);
  e parcial.examenes%rowtype;
  v_ult parcial.eventos%rowtype;
  v_n int;
begin
  select * into e from parcial.examenes where id = v_ex;
  if e.estado <> 'en_curso' or now() >= e.termina_en then return; end if;
  if p_tipo not in ('salio', 'volvio', 'copio') then raise exception 'Evento inválido'; end if;
  -- Tope para que un cliente alterado no llene la tabla.
  if (select count(*) from parcial.eventos where examen_id = v_ex) >= 1000 then return; end if;

  select count(*) + 1 into v_n
    from parcial.examen_preguntas where examen_id = v_ex and respondida_en is not null;

  -- Última salida/regreso: evita contar dos veces la misma salida (p. ej. pierde
  -- el foco y luego oculta la pestaña) y empareja cada regreso con su salida.
  select * into v_ult from parcial.eventos
   where examen_id = v_ex and tipo in ('salio', 'volvio') order by id desc limit 1;

  if p_tipo = 'salio' then
    if v_ult.tipo = 'salio' then return; end if;
    insert into parcial.eventos (examen_id, tipo, motivo, pregunta_n)
    values (v_ex, 'salio', left(p_motivo, 20), v_n);
  elsif p_tipo = 'volvio' then
    if v_ult.tipo is distinct from 'salio' then return; end if;
    insert into parcial.eventos (examen_id, tipo, pregunta_n, segundos)
    values (v_ex, 'volvio', v_n, greatest(0, round(extract(epoch from now() - v_ult.en)))::int);
  else
    insert into parcial.eventos (examen_id, tipo, pregunta_n) values (v_ex, 'copio', v_n);
  end if;
end $$;

-- Resumen por examen: salidas, segundos fuera (incluye la salida aún abierta),
-- si está fuera ahora mismo y cuántas veces copió.
create or replace function parcial._resumen_eventos(p_ex int) returns jsonb
language sql stable security definer set search_path = parcial, extensions, pg_temp as $$
  with ult as (
    select tipo, en from parcial.eventos
     where examen_id = p_ex and tipo in ('salio', 'volvio') order by id desc limit 1),
  ex as (select estado, finalizado_en, termina_en from parcial.examenes where id = p_ex)
  select jsonb_build_object(
    'salidas', count(*) filter (where ev.tipo = 'salio'),
    'copias', count(*) filter (where ev.tipo = 'copio'),
    'seg_fuera', coalesce(sum(ev.segundos) filter (where ev.tipo = 'volvio'), 0)
      + coalesce((select greatest(0, round(extract(epoch from
            least(coalesce(ex.finalizado_en, now()), ex.termina_en) - ult.en)))::int
          from ult, ex where ult.tipo = 'salio'), 0),
    'fuera_ahora', exists (select 1 from ult, ex where ult.tipo = 'salio' and ex.estado = 'en_curso'))
  from parcial.eventos ev where ev.examen_id = p_ex
$$;

create or replace function public.parcial_admin_resultados(p_clave text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
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

create or replace function public.parcial_admin_detalle(p_clave text, p_estudiante_id int) returns jsonb
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
        'puntos', e.puntos_obtenidos, 'puntos_max', e.puntaje_max, 'nivel', e.nivel,
        'total', e.n_preguntas) || parcial._resumen_eventos(e.id) end,
    'eventos', case when e.id is null then '[]'::jsonb else coalesce((
        select jsonb_agg(jsonb_build_object('tipo', ev.tipo, 'motivo', ev.motivo, 'en', ev.en,
                                            'pregunta_n', ev.pregunta_n, 'segundos', ev.segundos)
                         order by ev.id)
          from parcial.eventos ev where ev.examen_id = e.id), '[]'::jsonb) end,
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

revoke all on function parcial._resumen_eventos(int) from public, anon, authenticated;
revoke all on function public.parcial_evento(uuid, text, text) from public;
grant execute on function public.parcial_evento(uuid, text, text) to anon, authenticated;
