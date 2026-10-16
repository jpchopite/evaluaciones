-- El estudiante ya no recibe su nota al terminar: los resultados son solo para el profesor.

create or replace function parcial._estado(p_ex int) returns jsonb
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
    -- La nota y los puntos son solo para el profesor: al estudiante solo se le
    -- confirma la entrega y el motivo del cierre.
    v_res := jsonb_build_object('motivo', e.motivo_fin, 'finalizado_en', e.finalizado_en);
  end if;

  return jsonb_build_object(
    'estado', e.estado,
    'restante_seg', greatest(0, floor(extract(epoch from (e.termina_en - now()))))::int,
    'respondidas', v_resp, 'total', v_tot,
    'pregunta', v_preg, 'resultado', v_res);
end $$;

revoke all on function parcial._estado(int) from public, anon, authenticated;
