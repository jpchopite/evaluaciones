-- Al terminar, el estudiante ve los puntos que obtuvo (sin el máximo ni la nota).
--
-- Único cambio respecto a 005: el resultado incluye 'puntos'. La nota sigue siendo
-- solo para el profesor, y el máximo (240) no se envía.

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
    -- Los puntos sí se muestran al estudiante; la nota y el máximo son solo para el profesor.
    v_res := jsonb_build_object('motivo', e.motivo_fin, 'finalizado_en', e.finalizado_en,
                                'puntos', coalesce(e.puntos_obtenidos, 0));
  end if;

  return jsonb_build_object(
    'estado', e.estado,
    'restante_seg', greatest(0, floor(extract(epoch from (e.termina_en - now()))))::int,
    'respondidas', v_resp, 'total', e.n_preguntas,
    'pregunta', v_preg, 'resultado', v_res);
end $$;

revoke all on function parcial._estado(int) from public, anon, authenticated;
