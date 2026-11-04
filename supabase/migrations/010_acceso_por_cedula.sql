-- Acceso sin código: el estudiante entra con su cédula y escribe su nombre.
--
-- Solo entran las cédulas de la lista cargada por el profesor (y activas). El nombre no se
-- valida: se guarda en cada ingreso como evento 'ingreso' (motivo = nombre escrito) para que
-- el profesor vea en el detalle quién dijo ser y detecte si no coincide con el registrado.
--
-- parcial_iniciar(cedula, codigo) se elimina: los códigos ya no dan acceso. La columna
-- estudiantes.codigo y el bloqueo por intentos fallidos quedan sin uso.

alter table parcial.eventos drop constraint if exists eventos_tipo_check;
alter table parcial.eventos add constraint eventos_tipo_check
  check (tipo in ('salio', 'volvio', 'copio', 'captura', 'foco', 'ingreso'));

drop function if exists public.parcial_iniciar(text, text);

create or replace function public.parcial_ingresar(p_cedula text, p_nombre text) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare
  s parcial.estudiantes%rowtype;
  ex parcial.examenes%rowtype;
  v_ced text := upper(regexp_replace(coalesce(p_cedula, ''), '[^0-9A-Za-z]', '', 'g'));
  v_nom text := left(regexp_replace(trim(coalesce(p_nombre, '')), '\s+', ' ', 'g'), 80);
  v_n int; v_dur int;
begin
  if length(v_nom) < 3 then
    return jsonb_build_object('error', 'Escribe tu nombre y apellido.');
  end if;
  select * into s from parcial.estudiantes where cedula = v_ced and activo for update;
  if not found then
    perform pg_sleep(1);
    return jsonb_build_object('error', 'Esa cédula no está en la lista del parcial. Revísala o consulta al profesor.');
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

revoke all on function public.parcial_ingresar(text, text) from public;
grant execute on function public.parcial_ingresar(text, text) to anon, authenticated;
