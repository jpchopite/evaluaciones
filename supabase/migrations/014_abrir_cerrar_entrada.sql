-- Abrir y cerrar la entrada al parcial desde el panel del profesor.
--
-- Con la entrada cerrada nadie puede EMPEZAR el parcial (ni inscribirse una cédula nueva).
-- Quien ya lo empezó puede volver a entrar para continuar (p. ej. si se le cayó la
-- conexión) o para ver sus puntos tras entregar. Por defecto queda abierta, como hasta ahora.

insert into parcial.config (clave, valor) values ('entrada_abierta', 'true') on conflict (clave) do nothing;

create or replace function parcial._entrada_abierta() returns boolean
language sql stable security definer set search_path = parcial, extensions, pg_temp as $$
  select coalesce((select valor = 'true' from parcial.config where clave = 'entrada_abierta'), true)
$$;

create or replace function public.parcial_ingresar(p_cedula text, p_nombre text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare
  s parcial.estudiantes%rowtype;
  ex parcial.examenes%rowtype;
  v_ced text := parcial._cedula(p_cedula);
  v_nom text := left(regexp_replace(trim(coalesce(p_nombre, '')), '\s+', ' ', 'g'), 80);
  v_n int; v_dur int;
  v_cerrada constant text := 'La entrada al parcial está cerrada. Consulta al profesor.';
begin
  if length(v_nom) < 3 then
    return jsonb_build_object('error', 'Escribe tu nombre y apellido.');
  end if;
  select * into s from parcial.estudiantes where cedula = v_ced for update;
  if not found then
    if not parcial._entrada_abierta() then
      return jsonb_build_object('error', v_cerrada);
    end if;
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
    if not parcial._entrada_abierta() then
      return jsonb_build_object('error', v_cerrada);
    end if;
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

create or replace function public.parcial_admin_entrada(p_clave text, p_abierta boolean) returns boolean
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
begin
  perform parcial._admin(p_clave);
  insert into parcial.config (clave, valor) values ('entrada_abierta', (p_abierta is not false)::text)
  on conflict (clave) do update set valor = excluded.valor;
  return parcial._entrada_abierta();
end $$;

create or replace function public.parcial_admin_banco(p_clave text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare v_perf int;
begin
  perform parcial._admin(p_clave);
  v_perf := parcial._puntaje_max(coalesce((select valor::int from parcial.config where clave = 'n_preguntas'), 50));
  return jsonb_build_object(
    'total', (select count(*) from parcial.preguntas where activa),
    'por_dificultad', (select coalesce(jsonb_object_agg(dificultad, n), '{}')
                         from (select dificultad, count(*) n from parcial.preguntas
                                where activa group by dificultad) x),
    'n_preguntas', (select valor from parcial.config where clave = 'n_preguntas'),
    'duracion_min', (select valor from parcial.config where clave = 'duracion_min'),
    'puntaje_perfecto', v_perf,
    'puntaje_ref', round(v_perf * parcial._escala()),
    'entrada_abierta', parcial._entrada_abierta());
end $$;

revoke all on function parcial._entrada_abierta() from public, anon, authenticated;
revoke all on function public.parcial_admin_entrada(text, boolean) from public;
grant execute on function public.parcial_admin_entrada(text, boolean) to anon, authenticated;
