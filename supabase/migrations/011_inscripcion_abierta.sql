-- Inscripción abierta: el estudiante entra con su cédula y su nombre sin estar en una lista.
--
-- Si la cédula no está registrada, se inscribe en ese momento con el nombre escrito.
-- Si ya está (cargada por el profesor o de un ingreso anterior), entra como antes.
-- Si el profesor la quitó de la lista (inactiva), no puede entrar.
--
-- Las cédulas se guardan normalizadas para que "12.345.678", "v-12345678" y "V012345678"
-- sean la misma persona: letra V o E (V por defecto) + dígitos sin ceros a la izquierda.
-- Para inscribirse sola, la cédula debe tener esa forma (5 a 9 dígitos); otras cédulas
-- (p. ej. pasaportes) solo entran si el profesor las carga.

create or replace function parcial._cedula(p text) returns text
language sql immutable as $$
  select case when s ~ '^[VE]?[0-9]+$'
              then coalesce(nullif(substring(s from '^[VE]'), ''), 'V')
                   || coalesce(nullif(ltrim(substring(s from '[0-9]+$'), '0'), ''), '0')
              else s end
    from (select upper(regexp_replace(coalesce(p, ''), '[^0-9A-Za-z]', '', 'g')) s) x
$$;

create or replace function public.parcial_ingresar(p_cedula text, p_nombre text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare
  s parcial.estudiantes%rowtype;
  ex parcial.examenes%rowtype;
  v_ced text := parcial._cedula(p_cedula);
  v_nom text := left(regexp_replace(trim(coalesce(p_nombre, '')), '\s+', ' ', 'g'), 80);
  v_n int; v_dur int;
begin
  if length(v_nom) < 3 then
    return jsonb_build_object('error', 'Escribe tu nombre y apellido.');
  end if;
  select * into s from parcial.estudiantes where cedula = v_ced for update;
  if not found then
    if v_ced !~ '^[VE][1-9][0-9]{4,8}$' then
      perform pg_sleep(1);
      return jsonb_build_object('error', 'Escribe una cédula válida, por ejemplo V-12345678.');
    end if;
    insert into parcial.estudiantes (cedula, nombre, codigo)
    values (v_ced, initcap(lower(v_nom)), '')
    on conflict (cedula) do nothing;
    select * into s from parcial.estudiantes where cedula = v_ced for update;
  end if;
  if not s.activo then
    return jsonb_build_object('error', 'Esta cédula no puede presentar el parcial. Consulta al profesor.');
  end if;

  select * into ex from parcial.examenes where estudiante_id = s.id and not anulado;
  if not found then
    if not exists (select 1 from parcial.preguntas where activa) then
      raise exception 'No hay preguntas cargadas en el banco';
    end if;
    v_n := coalesce((select valor::int from parcial.config where clave = 'n_preguntas'), 50);
    v_dur := coalesce((select valor::int from parcial.config where clave = 'duracion_min'), 120);
    insert into parcial.examenes (estudiante_id, termina_en, n_preguntas, puntaje_max)
    values (s.id, now() + make_interval(mins => v_dur), v_n, parcial._puntaje_max(v_n))
    returning * into ex;
  end if;

  if ex.estado = 'en_curso' and now() < ex.termina_en then
    insert into parcial.eventos (examen_id, tipo, motivo, pregunta_n)
    values (ex.id, 'ingreso', v_nom,
            (select count(*) + 1 from parcial.examen_preguntas
              where examen_id = ex.id and respondida_en is not null));
  end if;

  return parcial._estado(ex.id)
      || jsonb_build_object('token', ex.token, 'nombre', s.nombre);
end $$;

-- La carga del profesor (opcional) normaliza igual, para que coincida con lo que escribe el estudiante.
create or replace function public.parcial_admin_cargar_estudiantes(p_clave text, p_estudiantes jsonb)
returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare n int;
begin
  perform parcial._admin(p_clave);
  insert into parcial.estudiantes (cedula, nombre, codigo)
  select distinct on (parcial._cedula(x->>'cedula')) parcial._cedula(x->>'cedula'), trim(x->>'nombre'), ''
    from jsonb_array_elements(p_estudiantes) x
   where parcial._cedula(x->>'cedula') <> ''
  on conflict (cedula) do update set nombre = excluded.nombre, activo = true;
  get diagnostics n = row_count;
  return jsonb_build_object('procesados', n);
end $$;

revoke all on function parcial._cedula(text) from public, anon, authenticated;
