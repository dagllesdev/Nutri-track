-- Ejecutar en Supabase SQL Editor después de db/init.sql.
-- Las tablas no se exponen directamente; la PWA solo usa estas funciones RPC.
ALTER TABLE ingredientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario ENABLE ROW LEVEL SECURITY;
ALTER TABLE historial_compras ENABLE ROW LEVEL SECURITY;
ALTER TABLE recetas ENABLE ROW LEVEL SECURITY;
ALTER TABLE detalle_receta ENABLE ROW LEVEL SECURITY;
ALTER TABLE registro_consumo ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api_capturador_ingredientes() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(data) ORDER BY data.categoria, data.nombre), '[]'::jsonb)
  FROM (SELECT i.id_ingrediente,i.nombre,i.categoria,i.unidad_medida,i.presentacion_compra,i.dias_ingesta_abreviado,i.stock_minimo_alerta,i.lugar_compra_predeterminado,i.cantidad_compra_estandar,
        inv.cantidad_disponible,inv.ubicacion,inv.estado_maduracion,ultimo.costo_unitario_calculado ultimo_precio_unitario
        FROM ingredientes i JOIN inventario inv USING(id_ingrediente)
        LEFT JOIN LATERAL (SELECT costo_unitario_calculado FROM historial_compras WHERE id_ingrediente=i.id_ingrediente ORDER BY fecha_compra DESC,id_compra DESC LIMIT 1) ultimo ON true) data;
$$;

CREATE OR REPLACE FUNCTION api_dashboard_inventario() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(data) ORDER BY data.estado DESC, data.nombre), '[]'::jsonb)
  FROM (SELECT i.nombre,i.unidad_medida,i.stock_minimo_alerta,SUM(inv.cantidad_disponible) cantidad_disponible,
    CASE WHEN SUM(inv.cantidad_disponible)<=i.stock_minimo_alerta THEN 'REABASTECER' ELSE 'OK' END estado
    FROM ingredientes i JOIN inventario inv USING(id_ingrediente) GROUP BY i.id_ingrediente) data;
$$;

CREATE OR REPLACE FUNCTION api_confirmar_compras(p_compras jsonb, p_fecha_hora timestamptz DEFAULT now()) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c jsonb; ingrediente record; previo numeric; nuevo record; ubic text; maduracion text; respuesta jsonb := '[]'::jsonb;
BEGIN
  IF jsonb_typeof(p_compras) <> 'array' OR jsonb_array_length(p_compras)=0 THEN RAISE EXCEPTION 'Incluya al menos una compra.' USING ERRCODE='22023'; END IF;
  FOR c IN SELECT value FROM jsonb_array_elements(p_compras) LOOP
    IF COALESCE((c->>'precio_pagado_total')::numeric,0)<=0 OR COALESCE((c->>'cantidad_comprada')::numeric,0)<=0 OR COALESCE(trim(c->>'lugar_compra'),'')='' THEN RAISE EXCEPTION 'Compra inválida.' USING ERRCODE='22023'; END IF;
    SELECT * INTO ingrediente FROM ingredientes WHERE id_ingrediente=(c->>'id_ingrediente')::int FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ingrediente inválido.' USING ERRCODE='22023'; END IF;
    SELECT costo_unitario_calculado INTO previo FROM historial_compras WHERE id_ingrediente=ingrediente.id_ingrediente ORDER BY fecha_compra DESC,id_compra DESC LIMIT 1;
    INSERT INTO historial_compras(id_ingrediente,fecha_compra,lugar_compra,presentacion_marca,precio_pagado_total,cantidad_comprada)
      VALUES(ingrediente.id_ingrediente,COALESCE(p_fecha_hora,now()),trim(c->>'lugar_compra'),NULLIF(trim(c->>'presentacion_marca'),''),(c->>'precio_pagado_total')::numeric,(c->>'cantidad_comprada')::numeric)
      RETURNING id_compra,costo_unitario_calculado INTO nuevo;
    SELECT ubicacion,estado_maduracion INTO ubic,maduracion FROM inventario WHERE id_ingrediente=ingrediente.id_ingrediente ORDER BY fecha_ultima_actualizacion DESC LIMIT 1;
    ubic:=COALESCE(NULLIF(c->>'ubicacion',''),ubic,'ALACENA'); maduracion:=COALESCE(NULLIF(c->>'estado_maduracion',''),maduracion,'N_A');
    INSERT INTO inventario(id_ingrediente,cantidad_disponible,ubicacion,estado_maduracion) VALUES(ingrediente.id_ingrediente,(c->>'cantidad_comprada')::numeric,ubic,maduracion)
      ON CONFLICT(id_ingrediente,ubicacion,estado_maduracion) DO UPDATE SET cantidad_disponible=inventario.cantidad_disponible+EXCLUDED.cantidad_disponible,fecha_ultima_actualizacion=now();
    respuesta:=respuesta || jsonb_build_array(jsonb_build_object('ingrediente',ingrediente.nombre,'id_compra',nuevo.id_compra,'costo_unitario',nuevo.costo_unitario_calculado,'variacion_porcentaje',CASE WHEN previo IS NULL OR previo=0 THEN NULL ELSE round((nuevo.costo_unitario_calculado-previo)/previo*100,2) END));
  END LOOP;
  RETURN jsonb_build_object('message','Compra confirmada e inventario actualizado.','compras',respuesta);
END; $$;

CREATE OR REPLACE FUNCTION api_registrar_consumo(p_id_receta int, p_porciones numeric DEFAULT 1, p_fecha_hora timestamptz DEFAULT now()) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE necesidad record; lote record; restante numeric; descuento numeric;
BEGIN
  IF p_porciones<=0 OR NOT EXISTS(SELECT 1 FROM recetas WHERE id_receta=p_id_receta) THEN RAISE EXCEPTION 'Receta o porciones inválidas.' USING ERRCODE='22023'; END IF;
  FOR necesidad IN SELECT id_ingrediente,cantidad_requerida*p_porciones cantidad FROM detalle_receta WHERE id_receta=p_id_receta LOOP
    restante:=necesidad.cantidad;
    FOR lote IN SELECT id_inventario,cantidad_disponible FROM inventario WHERE id_ingrediente=necesidad.id_ingrediente AND cantidad_disponible>0 ORDER BY fecha_ultima_actualizacion FOR UPDATE LOOP
      descuento:=LEAST(restante,lote.cantidad_disponible); UPDATE inventario SET cantidad_disponible=cantidad_disponible-descuento,fecha_ultima_actualizacion=now() WHERE id_inventario=lote.id_inventario; restante:=restante-descuento; EXIT WHEN restante<=0;
    END LOOP;
    IF restante>0 THEN RAISE EXCEPTION 'Stock insuficiente para registrar el consumo.' USING ERRCODE='22023'; END IF;
  END LOOP;
  INSERT INTO registro_consumo(id_receta,fecha_hora,porciones_consumidas) VALUES(p_id_receta,COALESCE(p_fecha_hora,now()),p_porciones);
  RETURN jsonb_build_object('message','Consumo registrado e inventario descontado.');
END; $$;

GRANT EXECUTE ON FUNCTION api_capturador_ingredientes(), api_dashboard_inventario(), api_confirmar_compras(jsonb,timestamptz), api_registrar_consumo(int,numeric,timestamptz) TO anon, authenticated;
