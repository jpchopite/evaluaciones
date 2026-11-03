-- Registro de capturas de pantalla (tecla Imprimir pantalla).
--
-- Nuevo tipo de evento 'captura': la página del estudiante lo envía cuando pulsa
-- la tecla Impr Pant (Windows). No detecta capturas en Mac, en celulares, con
-- otras herramientas ni fotos de la pantalla.

alter table parcial.eventos drop constraint if exists eventos_tipo_check;
alter table parcial.eventos add constraint eventos_tipo_check
  check (tipo in ('salio', 'volvio', 'copio', 'captura'));

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
  if p_tipo not in ('salio', 'volvio', 'copio', 'captura') then raise exception 'Evento inválido'; end if;
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
    insert into parcial.eventos (examen_id, tipo, pregunta_n) values (v_ex, p_tipo, v_n);
  end if;
end $$;

create or replace function parcial._resumen_eventos(p_ex int) returns jsonb
language sql stable security definer set search_path = parcial, extensions, pg_temp as $$
  with ult as (
    select tipo, en from parcial.eventos
     where examen_id = p_ex and tipo in ('salio', 'volvio') order by id desc limit 1),
  ex as (select estado, finalizado_en, termina_en from parcial.examenes where id = p_ex)
  select jsonb_build_object(
    'salidas', count(*) filter (where ev.tipo = 'salio'),
    'copias', count(*) filter (where ev.tipo = 'copio'),
    'capturas', count(*) filter (where ev.tipo = 'captura'),
    'seg_fuera', coalesce(sum(ev.segundos) filter (where ev.tipo = 'volvio'), 0)
      + coalesce((select greatest(0, round(extract(epoch from
            least(coalesce(ex.finalizado_en, now()), ex.termina_en) - ult.en)))::int
          from ult, ex where ult.tipo = 'salio'), 0),
    'fuera_ahora', exists (select 1 from ult, ex where ult.tipo = 'salio' and ex.estado = 'en_curso'))
  from parcial.eventos ev where ev.examen_id = p_ex
$$;

revoke all on function parcial._resumen_eventos(int) from public, anon, authenticated;
revoke all on function public.parcial_evento(uuid, text, text) from public;
grant execute on function public.parcial_evento(uuid, text, text) to anon, authenticated;
