-- Volver a cargar una cédula que se había quitado de la lista la reactiva
-- (antes solo actualizaba el nombre y el estudiante seguía sin poder ingresar).
create or replace function public.parcial_admin_cargar_estudiantes(p_clave text, p_estudiantes jsonb)
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
  on conflict (cedula) do update set nombre = excluded.nombre, activo = true;
  get diagnostics n = row_count;
  return jsonb_build_object('procesados', n);
end $$;
