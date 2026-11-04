-- Escala de notas ajustable: puntaje de referencia.
--
-- Nota = puntos obtenidos ÷ puntaje de referencia × 20, con tope en 20.
-- Por defecto la referencia es el recorrido perfecto (240 con 50 preguntas), como hasta ahora.
-- El profesor puede bajarla desde Ajustes (por ejemplo a 165) y se recalifican al instante
-- todos los exámenes ya finalizados. Los puntos y el orden entre estudiantes no cambian.
--
-- Se guarda como fracción del recorrido perfecto (config 'escala', 165 / 240 = 0,6875) para que
-- siga valiendo si cambia el número de preguntas. puntaje_max sigue siendo el recorrido perfecto.

insert into parcial.config (clave, valor) values ('escala', '1') on conflict (clave) do nothing;

create or replace function parcial._escala() returns numeric
language sql stable security definer set search_path = parcial, extensions, pg_temp as $$
  select coalesce((select valor::numeric from parcial.config where clave = 'escala'), 1)
$$;

create or replace function parcial._nota(p_pts numeric, p_max numeric) returns numeric
language sql stable security definer set search_path = parcial, extensions, pg_temp as $$
  select case when coalesce(p_max, 0) > 0
              then least(20, round(coalesce(p_pts, 0) / (p_max * parcial._escala()) * 20, 2))
              else 0 end
$$;

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
         puntaje = parcial._nota(v_pts, v_max)
   where id = p_ex and estado = 'en_curso';
end $$;

-- p_referencia: puntos para sacar 20 con el número de preguntas actual (null = recorrido perfecto).
-- Devuelve cuántos exámenes finalizados se recalificaron.
create or replace function public.parcial_admin_escala(p_clave text, p_referencia numeric) returns jsonb
language plpgsql security definer set search_path = parcial, extensions, pg_temp as $$
declare v_perf int; v_esc numeric; v_n int;
begin
  perform parcial._admin(p_clave);
  v_perf := parcial._puntaje_max(coalesce((select valor::int from parcial.config where clave = 'n_preguntas'), 50));
  if p_referencia is null then p_referencia := v_perf; end if;
  if p_referencia < ceil(v_perf * 0.5) or p_referencia > v_perf then
    raise exception 'El puntaje de referencia debe estar entre % y %', ceil(v_perf * 0.5), v_perf;
  end if;
  v_esc := p_referencia / v_perf;
  insert into parcial.config (clave, valor) values ('escala', v_esc::text)
  on conflict (clave) do update set valor = excluded.valor;
  update parcial.examenes
     set puntaje = parcial._nota(puntos_obtenidos, puntaje_max)
   where estado = 'finalizado';
  get diagnostics v_n = row_count;
  return jsonb_build_object('referencia', p_referencia, 'recalificados', v_n);
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
    'puntaje_ref', round(v_perf * parcial._escala()));
end $$;

revoke all on function parcial._escala(), parcial._nota(numeric, numeric), parcial._finalizar(int, text)
  from public, anon, authenticated;
revoke all on function public.parcial_admin_escala(text, numeric) from public;
grant execute on function public.parcial_admin_escala(text, numeric) to anon, authenticated;
