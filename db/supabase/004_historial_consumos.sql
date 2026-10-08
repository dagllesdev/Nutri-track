-- Ejecutar después de 003_barras_stock.sql.
ALTER TABLE registro_consumo
  ADD COLUMN IF NOT EXISTS costo_receta_calculado DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS porcentaje_descontado_total DECIMAL(8,2) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS detalle_registro_consumo (
  id_detalle_consumo SERIAL PRIMARY KEY,
  id_consumo INT NOT NULL REFERENCES registro_consumo(id_consumo) ON DELETE CASCADE,
  id_ingrediente INT NOT NULL REFERENCES ingredientes(id_ingrediente),
  cantidad_descontada DECIMAL(10,2) NOT NULL,
  stock_antes DECIMAL(10,2) NOT NULL,
  costo_unitario DECIMAL(12,4) NOT NULL DEFAULT 0,
  costo_total DECIMAL(12,2) NOT NULL DEFAULT 0,
  porcentaje_descontado DECIMAL(8,2) NOT NULL DEFAULT 0
);

CREATE OR REPLACE FUNCTION api_registrar_consumo(p_id_receta int, p_porciones numeric DEFAULT 1, p_fecha_hora timestamptz DEFAULT now()) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE necesidad record; lote record; restante numeric; descuento numeric; consumo_id int;
  stock_previo numeric; costo numeric; costo_total_receta numeric := 0; impacto_total numeric := 0; ingredientes_contados int := 0;
BEGIN
  IF p_porciones <= 0 OR NOT EXISTS(SELECT 1 FROM recetas WHERE id_receta=p_id_receta) THEN
    RAISE EXCEPTION 'Receta o porciones inválidas.' USING ERRCODE='22023';
  END IF;
  INSERT INTO registro_consumo(id_receta, fecha_hora, porciones_consumidas)
  VALUES(p_id_receta, COALESCE(p_fecha_hora, now()), p_porciones) RETURNING id_consumo INTO consumo_id;
  FOR necesidad IN SELECT id_ingrediente, cantidad_requerida * p_porciones AS cantidad FROM detalle_receta WHERE id_receta=p_id_receta LOOP
    SELECT COALESCE(SUM(cantidad_disponible),0) INTO stock_previo FROM inventario WHERE id_ingrediente=necesidad.id_ingrediente;
    IF stock_previo < necesidad.cantidad THEN RAISE EXCEPTION 'Stock insuficiente para registrar el consumo.' USING ERRCODE='22023'; END IF;
    SELECT COALESCE(SUM(precio_pagado_total)/NULLIF(SUM(cantidad_comprada),0),0) INTO costo
    FROM historial_compras WHERE id_ingrediente=necesidad.id_ingrediente
      AND fecha_compra=(SELECT MAX(fecha_compra) FROM historial_compras WHERE id_ingrediente=necesidad.id_ingrediente);
    restante:=necesidad.cantidad;
    FOR lote IN SELECT id_inventario,cantidad_disponible FROM inventario WHERE id_ingrediente=necesidad.id_ingrediente AND cantidad_disponible>0 ORDER BY fecha_ultima_actualizacion FOR UPDATE LOOP
      descuento:=LEAST(restante,lote.cantidad_disponible);
      UPDATE inventario SET cantidad_disponible=cantidad_disponible-descuento,fecha_ultima_actualizacion=now() WHERE id_inventario=lote.id_inventario;
      restante:=restante-descuento; EXIT WHEN restante<=0;
    END LOOP;
    INSERT INTO detalle_registro_consumo(id_consumo,id_ingrediente,cantidad_descontada,stock_antes,costo_unitario,costo_total,porcentaje_descontado)
    VALUES(consumo_id,necesidad.id_ingrediente,necesidad.cantidad,stock_previo,costo,necesidad.cantidad*costo,ROUND(necesidad.cantidad/NULLIF(stock_previo,0)*100,2));
    costo_total_receta:=costo_total_receta+necesidad.cantidad*costo;
    impacto_total:=impacto_total+necesidad.cantidad/NULLIF(stock_previo,0)*100; ingredientes_contados:=ingredientes_contados+1;
  END LOOP;
  UPDATE registro_consumo SET costo_receta_calculado=ROUND(costo_total_receta,2), porcentaje_descontado_total=ROUND(impacto_total/NULLIF(ingredientes_contados,0),2) WHERE id_consumo=consumo_id;
  RETURN jsonb_build_object('message','Consumo registrado e inventario descontado.','id_consumo',consumo_id);
END; $$;

CREATE OR REPLACE FUNCTION api_historial_consumos() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(data) ORDER BY data.fecha_hora DESC), '[]'::jsonb)
  FROM (
    SELECT rc.id_consumo,rc.fecha_hora,r.nombre AS nombre_receta,rc.costo_receta_calculado,rc.porcentaje_descontado_total,
      jsonb_agg(jsonb_build_object('nombre',i.nombre,'unidad_medida',i.unidad_medida,'cantidad_descontada',d.cantidad_descontada,'costo_total',d.costo_total,'porcentaje_descontado',d.porcentaje_descontado) ORDER BY i.nombre) AS detalles
    FROM registro_consumo rc JOIN recetas r USING(id_receta)
    JOIN detalle_registro_consumo d USING(id_consumo) JOIN ingredientes i USING(id_ingrediente)
    GROUP BY rc.id_consumo,r.nombre
    ORDER BY rc.fecha_hora DESC LIMIT 50
  ) data;
$$;

GRANT EXECUTE ON FUNCTION api_registrar_consumo(int,numeric,timestamptz), api_historial_consumos() TO anon, authenticated;
