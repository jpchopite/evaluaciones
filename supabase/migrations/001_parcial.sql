-- Parcial Diplomado Petróleo y Gas UCAB
-- Todo vive en el esquema "parcial" (no expuesto por la API). El navegador solo
-- puede llamar a las funciones public.parcial_* (SECURITY DEFINER).

create extension if not exists pgcrypto with schema extensions;
create schema if not exists parcial;

-- ───────────────────────── Tablas ─────────────────────────
create table parcial.config (
  clave text primary key,
  valor text not null
);
insert into parcial.config (clave, valor) values
  ('duracion_min', '120'),
  ('n_preguntas', '50');

create table parcial.preguntas (
  id int generated always as identity primary key,
  tema text,
  enunciado text not null,
  opciones jsonb not null
    check (jsonb_typeof(opciones) = 'array' and jsonb_array_length(opciones) between 2 and 5),
  correcta smallint not null check (correcta >= 0),         -- índice 0-based
  dificultad smallint not null check (dificultad between 1 and 5),  -- también es la ponderación
  activa boolean not null default true,
  creada_en timestamptz not null default now(),
  check (correcta < jsonb_array_length(opciones))
);

create table parcial.estudiantes (
  id int generated always as identity primary key,
  cedula text not null unique,
  nombre text not null,
  codigo text not null,
  activo boolean not null default true,
  fallos int not null default 0,
  bloqueado_hasta timestamptz
);

-- Un estudiante puede tener varios exámenes, pero solo uno no anulado.
-- "Reiniciar" anula el examen anterior (queda como rastro de auditoría).
create table parcial.examenes (
  id int generated always as identity primary key,
  estudiante_id int not null references parcial.estudiantes (id) on delete cascade,
  anulado boolean not null default false,
  token uuid not null unique default gen_random_uuid(),
  iniciado_en timestamptz not null default now(),
  termina_en timestamptz not null,
  finalizado_en timestamptz,
  estado text not null default 'en_curso' check (estado in ('en_curso', 'finalizado')),
  motivo_fin text,
  nivel int not null default 1 check (nivel between 1 and 5),
  puntos_obtenidos numeric,
  puntaje_max numeric,
  puntaje numeric            -- nota sobre 20
);

create unique index examenes_estudiante_activo on parcial.examenes (estudiante_id) where not anulado;

create table parcial.examen_preguntas (
  id int generated always as identity primary key,
  examen_id int not null references parcial.examenes (id) on delete cascade,
  pregunta_id int not null references parcial.preguntas (id),
  orden_opciones smallint[] not null,   -- permutación de opciones mostrada a este estudiante
  orden_presentacion int,
  nivel_al_presentar int,
  presentada_en timestamptz,
  respondida_en timestamptz,
  opcion_elegida smallint,              -- posición mostrada (0-based)
  es_correcta boolean,
  puntos numeric not null default 0,
  unique (examen_id, pregunta_id)
);
create index on parcial.examen_preguntas (examen_id);

alter table parcial.config enable row level security;
alter table parcial.preguntas enable row level security;
alter table parcial.estudiantes enable row level security;
alter table parcial.examenes enable row level security;
alter table parcial.examen_preguntas enable row level security;
revoke all on schema parcial from public, anon, authenticated;
revoke all on all tables in schema parcial from public, anon, authenticated;

-- ───────────────────── Funciones internas ─────────────────────
create function parcial._admin(p_clave text) returns void
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare v_hash text;
begin
  select valor into v_hash from parcial.config where clave = 'admin_hash';
  if v_hash is null or extensions.crypt(coalesce(p_clave, ''), v_hash) <> v_hash then
    perform pg_sleep(1.5);
    raise exception 'No autorizado';
  end if;
end $$;

create function parcial._finalizar(p_ex int, p_motivo text) returns void
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare v_pts numeric; v_max numeric;
begin
  select coalesce(sum(ep.puntos), 0), coalesce(sum(p.dificultad), 0)
    into v_pts, v_max
    from parcial.examen_preguntas ep
    join parcial.preguntas p on p.id = ep.pregunta_id
   where ep.examen_id = p_ex;
  update parcial.examenes
     set estado = 'finalizado', finalizado_en = now(), motivo_fin = p_motivo,
         puntos_obtenidos = v_pts, puntaje_max = v_max,
         puntaje = case when v_max > 0 then round(v_pts / v_max * 20, 2) else 0 end
   where id = p_ex and estado = 'en_curso';
end $$;

-- Estado actual del examen. Aquí vive el algoritmo adaptivo:
-- toma, entre las preguntas aún no presentadas, la de dificultad más cercana al
-- nivel actual del estudiante (empate al azar).
create function parcial._estado(p_ex int) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare
  e parcial.examenes%rowtype;
  v_ep parcial.examen_preguntas%rowtype;
  v_p parcial.preguntas%rowtype;
  v_resp int; v_tot int; v_opts jsonb;
  v_preg jsonb := null; v_res jsonb := null;
begin
  select * into e from parcial.examenes where id = p_ex for update;

  if e.estado = 'en_curso' and now() >= e.termina_en then
    perform parcial._finalizar(p_ex, 'tiempo_agotado');
    select * into e from parcial.examenes where id = p_ex;
  end if;

  if e.estado = 'en_curso' then
    select * into v_ep from parcial.examen_preguntas
     where examen_id = p_ex and presentada_en is not null and respondida_en is null
     limit 1;
    if not found then
      select ep.* into v_ep
        from parcial.examen_preguntas ep
        join parcial.preguntas p on p.id = ep.pregunta_id
       where ep.examen_id = p_ex and ep.presentada_en is null
       order by abs(p.dificultad - e.nivel), random()
       limit 1;
      if not found then
        perform parcial._finalizar(p_ex, 'completado');
        select * into e from parcial.examenes where id = p_ex;
      else
        update parcial.examen_preguntas
           set presentada_en = now(),
               nivel_al_presentar = e.nivel,
               orden_presentacion = (select count(*) + 1 from parcial.examen_preguntas
                                      where examen_id = p_ex and presentada_en is not null)
         where id = v_ep.id
         returning * into v_ep;
      end if;
    end if;
  end if;

  select count(*) filter (where respondida_en is not null), count(*)
    into v_resp, v_tot
    from parcial.examen_preguntas where examen_id = p_ex;

  if e.estado = 'en_curso' then
    select * into v_p from parcial.preguntas where id = v_ep.pregunta_id;
    select jsonb_agg(v_p.opciones ->> (t.idx::int) order by t.ord)
      into v_opts
      from unnest(v_ep.orden_opciones) with ordinality as t(idx, ord);
    v_preg := jsonb_build_object(
      'id', v_p.id, 'tema', v_p.tema, 'enunciado', v_p.enunciado,
      'opciones', v_opts, 'peso', v_p.dificultad, 'numero', v_resp + 1);
  else
    v_res := jsonb_build_object(
      'nota', e.puntaje, 'puntos', e.puntos_obtenidos,
      'puntos_max', e.puntaje_max, 'motivo', e.motivo_fin);
  end if;

  return jsonb_build_object(
    'estado', e.estado,
    'restante_seg', greatest(0, floor(extract(epoch from (e.termina_en - now()))))::int,
    'respondidas', v_resp, 'total', v_tot,
    'pregunta', v_preg, 'resultado', v_res);
end $$;

create function parcial._ex_por_token(p_token uuid) returns int
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare v int;
begin
  select id into v from parcial.examenes where token = p_token and not anulado;
  if v is null then raise exception 'Sesión inválida'; end if;
  return v;
end $$;

-- ───────────────────── API de estudiantes ─────────────────────
create function public.parcial_iniciar(p_cedula text, p_codigo text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare
  s parcial.estudiantes%rowtype;
  ex parcial.examenes%rowtype;
  v_ced text := upper(regexp_replace(coalesce(p_cedula, ''), '[^0-9A-Za-z]', '', 'g'));
  v_n int; v_dur int; v_ids int[];
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
    v_n := coalesce((select valor::int from parcial.config where clave = 'n_preguntas'), 50);
    v_dur := coalesce((select valor::int from parcial.config where clave = 'duracion_min'), 120);

    insert into parcial.examenes (estudiante_id, termina_en)
    values (s.id, now() + make_interval(mins => v_dur))
    returning * into ex;

    -- Selección estratificada: n/5 preguntas al azar por cada nivel de dificultad,
    -- así todos los estudiantes tienen el mismo puntaje máximo posible.
    select array_agg(id) into v_ids from (
      select id, row_number() over (partition by dificultad order by random()) rn
        from parcial.preguntas where activa
    ) r where rn <= v_n / 5;
    v_ids := coalesce(v_ids, '{}');
    if cardinality(v_ids) < v_n then
      select v_ids || coalesce(array_agg(id), '{}') into v_ids from (
        select id from parcial.preguntas
         where activa and id <> all (v_ids)
         order by random() limit v_n - cardinality(v_ids)
      ) y;
    end if;
    if cardinality(v_ids) = 0 then
      raise exception 'No hay preguntas cargadas en el banco';
    end if;

    insert into parcial.examen_preguntas (examen_id, pregunta_id, orden_opciones)
    select ex.id, p.id,
           (select array_agg(g::smallint order by random())
              from generate_series(0, jsonb_array_length(p.opciones) - 1) g
             where p.id is not null)
      from parcial.preguntas p
     where p.id = any (v_ids);
  end if;

  return parcial._estado(ex.id)
      || jsonb_build_object('token', ex.token, 'nombre', s.nombre);
end $$;

create function public.parcial_estado(p_token uuid) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare v_ex int := parcial._ex_por_token(p_token);
begin
  return parcial._estado(v_ex);
end $$;

create function public.parcial_responder(p_token uuid, p_pregunta_id int, p_opcion int) returns jsonb
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

  update parcial.examen_preguntas
     set respondida_en = now(), opcion_elegida = p_opcion, es_correcta = v_ok,
         puntos = case when v_ok then p.dificultad else 0 end
   where id = ep.id;

  -- Acierta: sube un nivel. Falla: baja un nivel.
  update parcial.examenes
     set nivel = case when v_ok then least(5, nivel + 1) else greatest(1, nivel - 1) end
   where id = v_ex;

  return parcial._estado(v_ex);
end $$;

create function public.parcial_finalizar(p_token uuid) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare v_ex int := parcial._ex_por_token(p_token);
begin
  perform parcial._finalizar(v_ex, 'entregado');
  return parcial._estado(v_ex);
end $$;

-- ───────────────────── API de administración ─────────────────────
create function public.parcial_admin_banco(p_clave text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  return jsonb_build_object(
    'total', (select count(*) from parcial.preguntas where activa),
    'por_dificultad', (select coalesce(jsonb_object_agg(dificultad, n), '{}')
                         from (select dificultad, count(*) n from parcial.preguntas
                                where activa group by dificultad) x),
    'n_preguntas', (select valor from parcial.config where clave = 'n_preguntas'),
    'duracion_min', (select valor from parcial.config where clave = 'duracion_min'));
end $$;

-- p_preguntas: [{tema, enunciado, opciones:[...], correcta:0-based, dificultad:1-5}]
create function public.parcial_admin_cargar_preguntas(p_clave text, p_preguntas jsonb, p_reemplazar boolean default false)
returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare n int;
begin
  perform parcial._admin(p_clave);
  if p_reemplazar then
    -- se desactivan (no se borran) para conservar el historial de exámenes ya tomados
    update parcial.preguntas set activa = false where activa;
  end if;
  insert into parcial.preguntas (tema, enunciado, opciones, correcta, dificultad)
  select x->>'tema', x->>'enunciado', x->'opciones',
         (x->>'correcta')::smallint, (x->>'dificultad')::smallint
    from jsonb_array_elements(p_preguntas) x;
  get diagnostics n = row_count;
  return jsonb_build_object('insertadas', n);
end $$;

-- p_estudiantes: [{cedula, nombre}]. Genera un código de acceso de 6 caracteres.
create function public.parcial_admin_cargar_estudiantes(p_clave text, p_estudiantes jsonb)
returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare n int;
begin
  perform parcial._admin(p_clave);
  insert into parcial.estudiantes (cedula, nombre, codigo)
  select upper(regexp_replace(x->>'cedula', '[^0-9A-Za-z]', '', 'g')),
         trim(x->>'nombre'),
         (select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789',
                   1 + (get_byte(extensions.gen_random_bytes(1), 0) % 31), 1), '')
            from generate_series(1, 6) g where x is not null)
    from jsonb_array_elements(p_estudiantes) x
   where coalesce(x->>'cedula', '') <> ''
  on conflict (cedula) do update set nombre = excluded.nombre;
  get diagnostics n = row_count;
  return jsonb_build_object('procesados', n);
end $$;

create function public.parcial_admin_resultados(p_clave text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'id', s.id, 'cedula', s.cedula, 'nombre', s.nombre, 'codigo', s.codigo,
        'estado', coalesce(e.estado, 'sin_iniciar'), 'motivo', e.motivo_fin,
        'respondidas', c.resp, 'correctas', c.ok, 'total', c.tot,
        'puntos', e.puntos_obtenidos, 'puntos_max', e.puntaje_max, 'nota', e.puntaje,
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

create function public.parcial_admin_reiniciar(p_clave text, p_estudiante_id int) returns void
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  update parcial.examenes set anulado = true where estudiante_id = p_estudiante_id and not anulado;
end $$;

create function public.parcial_admin_eliminar_estudiante(p_clave text, p_estudiante_id int) returns void
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  update parcial.estudiantes set activo = false where id = p_estudiante_id;
end $$;

create function public.parcial_admin_config(p_clave text, p_duracion_min int, p_n_preguntas int) returns void
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  if p_duracion_min < 1 or p_n_preguntas < 5 then raise exception 'Valores inválidos'; end if;
  update parcial.config set valor = p_duracion_min::text where clave = 'duracion_min';
  update parcial.config set valor = p_n_preguntas::text where clave = 'n_preguntas';
end $$;

create function public.parcial_admin_cambiar_clave(p_clave text, p_nueva text) returns void
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  if length(coalesce(p_nueva, '')) < 8 then raise exception 'La clave debe tener al menos 8 caracteres'; end if;
  insert into parcial.config (clave, valor)
  values ('admin_hash', extensions.crypt(p_nueva, extensions.gen_salt('bf')))
  on conflict (clave) do update set valor = excluded.valor;
end $$;

-- ───────────────────── Clave de administrador ─────────────────────
-- Se fija aparte (no en este archivo) para no guardar la clave en el repositorio:
--   insert into parcial.config (clave, valor)
--   values ('admin_hash', extensions.crypt('TU_CLAVE_SEGURA', extensions.gen_salt('bf')))
--   on conflict (clave) do update set valor = excluded.valor;

-- ───────────────────── Permisos ─────────────────────
revoke all on all functions in schema parcial from public, anon, authenticated;
revoke all on function
  public.parcial_iniciar(text, text), public.parcial_estado(uuid),
  public.parcial_responder(uuid, int, int), public.parcial_finalizar(uuid),
  public.parcial_admin_banco(text), public.parcial_admin_cargar_preguntas(text, jsonb, boolean),
  public.parcial_admin_cargar_estudiantes(text, jsonb), public.parcial_admin_resultados(text),
  public.parcial_admin_reiniciar(text, int), public.parcial_admin_eliminar_estudiante(text, int),
  public.parcial_admin_config(text, int, int), public.parcial_admin_cambiar_clave(text, text)
  from public;
grant execute on function
  public.parcial_iniciar(text, text), public.parcial_estado(uuid),
  public.parcial_responder(uuid, int, int), public.parcial_finalizar(uuid),
  public.parcial_admin_banco(text), public.parcial_admin_cargar_preguntas(text, jsonb, boolean),
  public.parcial_admin_cargar_estudiantes(text, jsonb), public.parcial_admin_resultados(text),
  public.parcial_admin_reiniciar(text, int), public.parcial_admin_eliminar_estudiante(text, int),
  public.parcial_admin_config(text, int, int), public.parcial_admin_cambiar_clave(text, text)
  to anon, authenticated;
