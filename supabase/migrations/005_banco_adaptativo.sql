-- Selección adaptativa desde el banco completo y nota sobre 20 con escala fija.
--
-- Antes: a cada estudiante se le asignaba un pool fijo (n/5 por nivel) y el algoritmo
-- solo decidía el orden. Ahora no hay pool: cada pregunta se saca al azar del banco
-- activo, del nivel en que está el estudiante:
--   · empieza en N1;
--   · acierta → la siguiente es de un nivel más (hasta N5, donde se queda mientras acierte);
--   · falla → la siguiente es de un nivel menos (nunca por debajo de N1).
--
-- Puntos: una pregunta acertada vale su nivel (N1 = 1 … N5 = 5).
-- Puntaje máximo = el de un recorrido perfecto de n preguntas: 1+2+3+4+5+5+…
-- (con 50 preguntas: 240). Es igual para todos, así que la nota es comparable:
--   nota = puntos obtenidos ÷ puntaje máximo × 20.
-- Lo no respondido cuenta 0.
--
-- Si un nivel se queda sin preguntas no vistas (banco chico), se toma la del nivel más
-- cercano y se acredita el nivel del estudiante, para que no pierda puntos por eso.

alter table parcial.examenes add column if not exists n_preguntas int;

-- Puntaje de un recorrido perfecto de p_n preguntas: 1, 2, 3, 4, 5, 5, 5…
create or replace function parcial._puntaje_max(p_n int) returns int
language sql immutable as $$
  select coalesce(sum(least(g, 5)), 0)::int from generate_series(1, p_n) g
$$;

-- Saca al azar una pregunta no vista del nivel pedido (o del más cercano si se agotó)
-- y la deja presentada. Devuelve null si el banco no tiene más preguntas.
create or replace function parcial._siguiente(p_ex int, p_nivel int) returns parcial.examen_preguntas
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare v_p parcial.preguntas%rowtype; v_ep parcial.examen_preguntas%rowtype;
begin
  select p.* into v_p
    from parcial.preguntas p
   where p.activa
     and not exists (select 1 from parcial.examen_preguntas ep
                      where ep.examen_id = p_ex and ep.pregunta_id = p.id)
   order by abs(p.dificultad - p_nivel), random()
   limit 1;
  if not found then return null; end if;

  insert into parcial.examen_preguntas
    (examen_id, pregunta_id, orden_opciones, orden_presentacion, nivel_al_presentar, presentada_en)
  values (p_ex, v_p.id,
          (select array_agg(g::smallint order by random())
             from generate_series(0, jsonb_array_length(v_p.opciones) - 1) g),
          (select count(*) + 1 from parcial.examen_preguntas where examen_id = p_ex),
          p_nivel, now())
  returning * into v_ep;
  return v_ep;
end $$;

create or replace function parcial._finalizar(p_ex int, p_motivo text) returns void
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare v_pts numeric; v_max numeric;
begin
  select coalesce(sum(ep.puntos), 0) into v_pts
    from parcial.examen_preguntas ep where ep.examen_id = p_ex;
  select coalesce(puntaje_max, 0) into v_max from parcial.examenes where id = p_ex;
  update parcial.examenes
     set estado = 'finalizado', finalizado_en = now(), motivo_fin = p_motivo,
         puntos_obtenidos = v_pts,
         puntaje = case when v_max > 0 then least(20, round(v_pts / v_max * 20, 2)) else 0 end
   where id = p_ex and estado = 'en_curso';
end $$;

create or replace function parcial._estado(p_ex int) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare
  e parcial.examenes%rowtype;
  v_ep parcial.examen_preguntas%rowtype;
  v_p parcial.preguntas%rowtype;
  v_resp int; v_opts jsonb;
  v_preg jsonb := null; v_res jsonb := null;
begin
  select * into e from parcial.examenes where id = p_ex for update;

  if e.estado = 'en_curso' and now() >= e.termina_en then
    perform parcial._finalizar(p_ex, 'tiempo_agotado');
    select * into e from parcial.examenes where id = p_ex;
  end if;

  select count(*) into v_resp
    from parcial.examen_preguntas where examen_id = p_ex and respondida_en is not null;

  if e.estado = 'en_curso' then
    select * into v_ep from parcial.examen_preguntas
     where examen_id = p_ex and presentada_en is not null and respondida_en is null
     limit 1;
    if not found then
      v_ep := null;
      if v_resp < e.n_preguntas then
        v_ep := parcial._siguiente(p_ex, e.nivel);
      end if;
      if v_ep.id is null then
        perform parcial._finalizar(p_ex, 'completado');
        select * into e from parcial.examenes where id = p_ex;
      end if;
    end if;
  end if;

  if e.estado = 'en_curso' then
    select * into v_p from parcial.preguntas where id = v_ep.pregunta_id;
    select jsonb_agg(v_p.opciones ->> (t.idx::int) order by t.ord)
      into v_opts
      from unnest(v_ep.orden_opciones) with ordinality as t(idx, ord);
    v_preg := jsonb_build_object(
      'id', v_p.id, 'tema', v_p.tema, 'enunciado', v_p.enunciado,
      'opciones', v_opts, 'peso', v_ep.nivel_al_presentar, 'numero', v_resp + 1);
  else
    -- La nota y los puntos son solo para el profesor.
    v_res := jsonb_build_object('motivo', e.motivo_fin, 'finalizado_en', e.finalizado_en);
  end if;

  return jsonb_build_object(
    'estado', e.estado,
    'restante_seg', greatest(0, floor(extract(epoch from (e.termina_en - now()))))::int,
    'respondidas', v_resp, 'total', e.n_preguntas,
    'pregunta', v_preg, 'resultado', v_res);
end $$;

create or replace function public.parcial_iniciar(p_cedula text, p_codigo text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare
  s parcial.estudiantes%rowtype;
  ex parcial.examenes%rowtype;
  v_ced text := upper(regexp_replace(coalesce(p_cedula, ''), '[^0-9A-Za-z]', '', 'g'));
  v_n int; v_dur int;
begin
  select * into s from parcial.estudiantes where cedula = v_ced and activo for update;
  if not found then
    perform pg_sleep(1);
    return jsonb_build_object('error', 'Cédula o código incorrectos');
  end if;
  if s.bloqueado_hasta is not null and s.bloqueado_hasta > now() then
    return jsonb_build_object('error', 'Demasiados intentos fallidos. Espera 5 minutos.');
  end if;
  if upper(trim(coalesce(p_codigo, ''))) <> s.codigo then
    update parcial.estudiantes
       set fallos = case when fallos + 1 >= 5 then 0 else fallos + 1 end,
           bloqueado_hasta = case when fallos + 1 >= 5 then now() + interval '5 minutes' else null end
     where id = s.id;
    perform pg_sleep(1);
    return jsonb_build_object('error', 'Cédula o código incorrectos');
  end if;
  update parcial.estudiantes set fallos = 0, bloqueado_hasta = null where id = s.id;

  select * into ex from parcial.examenes where estudiante_id = s.id and not anulado;
  if not found then
    if not exists (select 1 from parcial.preguntas where activa) then
      raise exception 'No hay preguntas cargadas en el banco';
    end if;
    v_n := coalesce((select valor::int from parcial.config where clave = 'n_preguntas'), 50);
    v_dur := coalesce((select valor::int from parcial.config where clave = 'duracion_min'), 120);
    -- Sin pool: las preguntas se sacan del banco una a una en parcial._estado.
    insert into parcial.examenes (estudiante_id, termina_en, n_preguntas, puntaje_max)
    values (s.id, now() + make_interval(mins => v_dur), v_n, parcial._puntaje_max(v_n))
    returning * into ex;
  end if;

  return parcial._estado(ex.id)
      || jsonb_build_object('token', ex.token, 'nombre', s.nombre);
end $$;

create or replace function public.parcial_responder(p_token uuid, p_pregunta_id int, p_opcion int) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare
  v_ex int := parcial._ex_por_token(p_token);
  e parcial.examenes%rowtype;
  ep parcial.examen_preguntas%rowtype;
  p parcial.preguntas%rowtype;
  v_ok boolean;
begin
  select * into e from parcial.examenes where id = v_ex for update;
  if e.estado <> 'en_curso' or now() >= e.termina_en then
    return parcial._estado(v_ex);
  end if;

  select * into ep from parcial.examen_preguntas
   where examen_id = v_ex and pregunta_id = p_pregunta_id
     and presentada_en is not null and respondida_en is null;
  if not found then raise exception 'Esa pregunta no está activa'; end if;
  if p_opcion is null or p_opcion < 0 or p_opcion >= cardinality(ep.orden_opciones) then
    raise exception 'Opción inválida';
  end if;

  select * into p from parcial.preguntas where id = ep.pregunta_id;
  v_ok := ep.orden_opciones[p_opcion + 1] = p.correcta;

  -- Vale el nivel en que se presentó (normalmente igual a su dificultad).
  update parcial.examen_preguntas
     set respondida_en = now(), opcion_elegida = p_opcion, es_correcta = v_ok,
         puntos = case when v_ok then ep.nivel_al_presentar else 0 end
   where id = ep.id;

  -- Acierta: sube un nivel. Falla: baja un nivel.
  update parcial.examenes
     set nivel = case when v_ok then least(5, nivel + 1) else greatest(1, nivel - 1) end
   where id = v_ex;

  return parcial._estado(v_ex);
end $$;

-- "total" es ahora el número de preguntas del examen, no las filas presentadas.
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
        'total', e.n_preguntas) end,
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

-- ───────────── Exámenes que ya existían ─────────────
-- Conservan su número de preguntas. A los que siguen en curso se les quita el pool
-- reservado (preguntas aún no presentadas, sin respuesta) y pasan a la escala fija;
-- los finalizados conservan su nota (ya era sobre 20).
update parcial.examenes e
   set n_preguntas = (select count(*) from parcial.examen_preguntas where examen_id = e.id)
 where n_preguntas is null;

delete from parcial.examen_preguntas ep
 using parcial.examenes e
 where e.id = ep.examen_id and e.estado = 'en_curso' and ep.presentada_en is null;

update parcial.examenes
   set puntaje_max = parcial._puntaje_max(n_preguntas)
 where estado = 'en_curso';

revoke all on function parcial._puntaje_max(int), parcial._siguiente(int, int),
  parcial._finalizar(int, text), parcial._estado(int) from public, anon, authenticated;
