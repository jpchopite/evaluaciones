-- Borra los estudiantes y exámenes del Parcial 1, DESPUÉS de archivarlo.
-- Se cancela sin borrar nada si el archivo no existe, si no tiene a todos los estudiantes
-- de la lista actual, si hay un examen en curso o si cambiara el cuestionario de San Tomé.
-- NO toca el banco de preguntas, la configuración ni el archivo.
do $$
declare v_arch int; v_act int; v_est int; v_ex int; v_resp int; v_org int;
begin
  select jsonb_array_length(resultados) into v_arch
    from parcial.archivos where titulo = 'Parcial 1 · Petróleo y Gas';
  select count(*) filter (where activo), count(*) into v_act, v_est from parcial.estudiantes;
  select count(*) into v_ex from parcial.examenes;
  select count(*) into v_resp from public.respuestas;
  select count(*) into v_org from private.organizadores;
  if v_arch is null then
    raise exception 'Cancelado: el Parcial 1 no está archivado todavía';
  end if;
  if v_arch <> v_act then
    raise exception 'Cancelado: el archivo tiene % estudiantes y la lista actual %', v_arch, v_act;
  end if;
  if exists (select 1 from parcial.examenes where estado = 'en_curso' and termina_en > now()) then
    raise exception 'Cancelado: hay un examen en curso';
  end if;
  -- Los exámenes, sus preguntas y sus eventos se borran en cascada. Solo esquema parcial.
  delete from parcial.estudiantes;
  if (select count(*) from public.respuestas) <> v_resp
     or (select count(*) from private.organizadores) <> v_org then
    raise exception 'Cancelado: cambió el cuestionario de San Tomé; no se borró nada';
  end if;
  raise notice 'Borrados: % estudiantes y % exámenes (archivados antes)', v_est, v_ex;
end $$;

select (select count(*) from parcial.estudiantes) estudiantes,
       (select count(*) from parcial.examenes) examenes,
       (select count(*) from parcial.archivos) archivos,
       (select count(*) from parcial.preguntas where activa) preguntas_activas,
       (select count(*) from public.respuestas) san_tome_respuestas;
