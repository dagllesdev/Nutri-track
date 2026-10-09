-- Ejecutar después de 004_historial_consumos.sql en Supabase SQL Editor.
-- Catálogo administrable y programación de recetas por día.

ALTER TABLE ingredientes
  ADD COLUMN IF NOT EXISTS tipos_comida text[] NOT NULL DEFAULT ARRAY['DESAYUNO']::text[],
  ADD COLUMN IF NOT EXISTS dias_uso text[] NOT NULL DEFAULT ARRAY[]::text[],
  ADD COLUMN IF NOT EXISTS precio_referencia_cop numeric(12,2),
  ADD COLUMN IF NOT EXISTS activo boolean NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS receta_programacion (
  id_receta int NOT NULL REFERENCES recetas(id_receta) ON DELETE CASCADE,
  dia_semana text NOT NULL CHECK (dia_semana IN ('Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo')),
  PRIMARY KEY (id_receta, dia_semana)
);

-- Conserva el menú actual al activar la nueva programación.
INSERT INTO receta_programacion(id_receta,dia_semana)
SELECT id_receta, dia
FROM recetas
CROSS JOIN LATERAL unnest(CASE nombre
  WHEN 'Sándwich Potenciado (Vie, Lun)' THEN ARRAY['Lunes','Viernes']
  WHEN 'Arepa Tradicional Proteica (Sab)' THEN ARRAY['Sábado']
  WHEN 'Tazón de Yogur & Granola (Dom, Mier)' THEN ARRAY['Miércoles','Domingo']
  WHEN 'Shake de Alta Densidad (Mar, Jue)' THEN ARRAY['Martes','Jueves']
  ELSE ARRAY[]::text[]
END) AS dia
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION api_catalogo_ingredientes() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.nombre), '[]'::jsonb)
  FROM (
    SELECT i.id_ingrediente,i.nombre,i.categoria,i.unidad_medida,i.stock_minimo_alerta,
      i.stock_objetivo_full,i.cantidad_compra_estandar,i.presentacion_compra,
      i.lugar_compra_predeterminado,i.precio_referencia_cop,i.tipos_comida,i.dias_uso,i.activo
    FROM ingredientes i
  ) x;
$$;

-- Los ingredientes pausados se conservan para las recetas históricas, pero no
-- se muestran en el Capturador de compras.
CREATE OR REPLACE FUNCTION api_capturador_ingredientes() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(data) ORDER BY data.categoria, data.nombre), '[]'::jsonb)
  FROM (
    SELECT i.id_ingrediente,i.nombre,i.categoria,i.unidad_medida,i.presentacion_compra,i.dias_ingesta_abreviado,
      i.stock_minimo_alerta,i.lugar_compra_predeterminado,i.cantidad_compra_estandar,i.stock_objetivo_full,
      inv.cantidad_disponible,GREATEST(i.stock_objetivo_full-inv.cantidad_disponible,0) cantidad_a_comprar,
      ultimo.costo_unitario_calculado ultimo_precio_unitario
    FROM ingredientes i
    JOIN LATERAL (SELECT COALESCE(SUM(cantidad_disponible),0) cantidad_disponible FROM inventario WHERE id_ingrediente=i.id_ingrediente) inv ON true
    LEFT JOIN LATERAL (SELECT costo_unitario_calculado FROM historial_compras WHERE id_ingrediente=i.id_ingrediente ORDER BY fecha_compra DESC,id_compra DESC LIMIT 1) ultimo ON true
    WHERE i.activo
  ) data;
$$;

CREATE OR REPLACE FUNCTION api_guardar_ingrediente(p_item jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE item_id int; unit text; name_value text;
BEGIN
  name_value := trim(COALESCE(p_item->>'nombre',''));
  unit := upper(COALESCE(p_item->>'unidad_medida',''));
  IF name_value='' OR unit NOT IN ('GRAMOS','UNIDADES','MILILITROS','CAPSULAS') THEN
    RAISE EXCEPTION 'Nombre y unidad de medida válidos son obligatorios.' USING ERRCODE='22023';
  END IF;
  IF COALESCE((p_item->>'stock_objetivo_full')::numeric,0)<0 OR COALESCE((p_item->>'stock_minimo_alerta')::numeric,0)<0 THEN
    RAISE EXCEPTION 'Los valores de stock no pueden ser negativos.' USING ERRCODE='22023';
  END IF;
  IF NULLIF(p_item->>'id_ingrediente','') IS NULL THEN
    INSERT INTO ingredientes(nombre,categoria,unidad_medida,stock_minimo_alerta,presentacion_compra,dias_ingesta_abreviado,lugar_compra_predeterminado,cantidad_compra_estandar,stock_objetivo_full,tipos_comida,dias_uso,precio_referencia_cop,activo)
    VALUES(name_value,COALESCE(NULLIF(upper(p_item->>'categoria'),''),'SECOS'),unit,
      COALESCE((p_item->>'stock_minimo_alerta')::numeric,0),COALESCE(NULLIF(trim(p_item->>'presentacion_compra'),''),'Sin presentación'),
      COALESCE(NULLIF(trim(p_item->>'dias_ingesta_abreviado'),''),'Diario'),COALESCE(NULLIF(trim(p_item->>'lugar_compra_habitual'),''),''),
      GREATEST(COALESCE((p_item->>'cantidad_compra_estandar')::numeric,1),0.01),COALESCE((p_item->>'stock_objetivo_full')::numeric,0),
      COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_item->'tipos_comida','[]'::jsonb))),ARRAY[]::text[]),
      COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_item->'dias_uso','[]'::jsonb))),ARRAY[]::text[]),
      NULLIF(p_item->>'precio_referencia_cop','')::numeric,COALESCE((p_item->>'activo')::boolean,true))
    RETURNING id_ingrediente INTO item_id;
    INSERT INTO inventario(id_ingrediente,cantidad_disponible,ubicacion,estado_maduracion)
    VALUES(item_id,0,'ALACENA','N_A') ON CONFLICT DO NOTHING;
  ELSE
    item_id := (p_item->>'id_ingrediente')::int;
    UPDATE ingredientes SET nombre=name_value,categoria=COALESCE(NULLIF(upper(p_item->>'categoria'),''),'SECOS'),unidad_medida=unit,
      stock_minimo_alerta=COALESCE((p_item->>'stock_minimo_alerta')::numeric,0),presentacion_compra=COALESCE(NULLIF(trim(p_item->>'presentacion_compra'),''),'Sin presentación'),
      dias_ingesta_abreviado=COALESCE(NULLIF(trim(p_item->>'dias_ingesta_abreviado'),''),'Diario'),lugar_compra_predeterminado=COALESCE(NULLIF(trim(p_item->>'lugar_compra_habitual'),''),''),
      cantidad_compra_estandar=GREATEST(COALESCE((p_item->>'cantidad_compra_estandar')::numeric,1),0.01),stock_objetivo_full=COALESCE((p_item->>'stock_objetivo_full')::numeric,0),
      tipos_comida=COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_item->'tipos_comida','[]'::jsonb))),ARRAY[]::text[]),
      dias_uso=COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_item->'dias_uso','[]'::jsonb))),ARRAY[]::text[]),
      precio_referencia_cop=NULLIF(p_item->>'precio_referencia_cop','')::numeric,activo=COALESCE((p_item->>'activo')::boolean,true)
    WHERE id_ingrediente=item_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ingrediente no encontrado.' USING ERRCODE='22023'; END IF;
  END IF;
  RETURN jsonb_build_object('id_ingrediente',item_id,'message','Ingrediente guardado.');
END;
$$;

CREATE OR REPLACE FUNCTION api_catalogo_recetas() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.nombre), '[]'::jsonb)
  FROM (
    SELECT r.id_receta,r.nombre,r.tipo_comida,r.calorias_estimadas,
      COALESCE((SELECT jsonb_agg(rp.dia_semana ORDER BY rp.dia_semana) FROM receta_programacion rp WHERE rp.id_receta=r.id_receta),'[]'::jsonb) dias,
      COALESCE((SELECT jsonb_agg(jsonb_build_object('id_ingrediente',i.id_ingrediente,'nombre',i.nombre,'unidad_medida',i.unidad_medida,'cantidad_requerida',d.cantidad_requerida) ORDER BY i.nombre) FROM detalle_receta d JOIN ingredientes i USING(id_ingrediente) WHERE d.id_receta=r.id_receta),'[]'::jsonb) ingredientes
    FROM recetas r
  ) x;
$$;

CREATE OR REPLACE FUNCTION api_guardar_receta(p_receta jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE recipe_id int; item jsonb; recipe_name text; recipe_type text;
BEGIN
  recipe_name:=trim(COALESCE(p_receta->>'nombre','')); recipe_type:=upper(COALESCE(p_receta->>'tipo_comida','DESAYUNO'));
  IF recipe_name='' OR recipe_type NOT IN ('DESAYUNO','ALMUERZO','CENA','SNACK') THEN RAISE EXCEPTION 'Nombre y tipo de receta válidos son obligatorios.' USING ERRCODE='22023'; END IF;
  IF jsonb_array_length(COALESCE(p_receta->'ingredientes','[]'::jsonb))=0 THEN RAISE EXCEPTION 'Agrega al menos un ingrediente.' USING ERRCODE='22023'; END IF;
  IF NULLIF(p_receta->>'id_receta','') IS NULL THEN
    INSERT INTO recetas(nombre,tipo_comida,calorias_estimadas) VALUES(recipe_name,recipe_type,COALESCE((p_receta->>'calorias_estimadas')::int,0)) RETURNING id_receta INTO recipe_id;
  ELSE
    recipe_id:=(p_receta->>'id_receta')::int;
    UPDATE recetas SET nombre=recipe_name,tipo_comida=recipe_type,calorias_estimadas=COALESCE((p_receta->>'calorias_estimadas')::int,0) WHERE id_receta=recipe_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Receta no encontrada.' USING ERRCODE='22023'; END IF;
    DELETE FROM detalle_receta WHERE id_receta=recipe_id;
  END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_receta->'ingredientes') LOOP
    IF COALESCE((item->>'cantidad_requerida')::numeric,0)<=0 OR NOT EXISTS(SELECT 1 FROM ingredientes WHERE id_ingrediente=(item->>'id_ingrediente')::int AND activo) THEN
      RAISE EXCEPTION 'Ingrediente o cantidad inválidos.' USING ERRCODE='22023';
    END IF;
    INSERT INTO detalle_receta(id_receta,id_ingrediente,cantidad_requerida) VALUES(recipe_id,(item->>'id_ingrediente')::int,(item->>'cantidad_requerida')::numeric);
  END LOOP;
  DELETE FROM receta_programacion WHERE id_receta=recipe_id;
  INSERT INTO receta_programacion(id_receta,dia_semana)
  SELECT recipe_id,day_name FROM jsonb_array_elements_text(COALESCE(p_receta->'dias','[]'::jsonb)) AS day_name
  WHERE day_name IN ('Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo');
  RETURN jsonb_build_object('id_receta',recipe_id,'message','Receta guardada.');
END;
$$;

CREATE OR REPLACE FUNCTION api_menu_diario(p_dia text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object('dia',p_dia,'id_receta',r.id_receta,'nombre',r.nombre,'calorias_estimadas',r.calorias_estimadas,
    'ingredientes',COALESCE(jsonb_agg(jsonb_build_object('nombre',i.nombre,'cantidad',d.cantidad_requerida,'unidad_medida',i.unidad_medida,'stock_disponible',COALESCE(inv.disponible,0),'stock_despues',GREATEST(COALESCE(inv.disponible,0)-d.cantidad_requerida,0),'faltante',GREATEST(d.cantidad_requerida-COALESCE(inv.disponible,0),0)) ORDER BY i.nombre) FILTER(WHERE i.id_ingrediente IS NOT NULL),'[]'::jsonb))
  FROM receta_programacion rp JOIN recetas r USING(id_receta) LEFT JOIN detalle_receta d USING(id_receta) LEFT JOIN ingredientes i USING(id_ingrediente)
  LEFT JOIN (SELECT id_ingrediente,SUM(cantidad_disponible) disponible FROM inventario GROUP BY id_ingrediente) inv USING(id_ingrediente)
  WHERE rp.dia_semana=p_dia GROUP BY r.id_receta,r.nombre,r.calorias_estimadas LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION api_catalogo_ingredientes(),api_guardar_ingrediente(jsonb),api_catalogo_recetas(),api_guardar_receta(jsonb),api_menu_diario(text) TO anon, authenticated;
