-- Ejecutar después de 005_catalogo_y_recetas.sql.
-- Cierre de CRUD: borrado seguro con pausa cuando existan registros históricos.

ALTER TABLE recetas ADD COLUMN IF NOT EXISTS activo boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION api_eliminar_ingrediente(p_id_ingrediente int) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM ingredientes WHERE id_ingrediente=p_id_ingrediente) THEN
    RAISE EXCEPTION 'Ingrediente no encontrado.' USING ERRCODE='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM historial_compras WHERE id_ingrediente=p_id_ingrediente)
    OR EXISTS(SELECT 1 FROM detalle_receta WHERE id_ingrediente=p_id_ingrediente)
    OR EXISTS(SELECT 1 FROM detalle_registro_consumo WHERE id_ingrediente=p_id_ingrediente) THEN
    UPDATE ingredientes SET activo=false WHERE id_ingrediente=p_id_ingrediente;
    RETURN jsonb_build_object('action','paused','message','El ingrediente tiene historial o recetas asociadas; fue pausado para conservar los datos.');
  END IF;
  DELETE FROM ingredientes WHERE id_ingrediente=p_id_ingrediente;
  RETURN jsonb_build_object('action','deleted','message','Ingrediente eliminado.');
END;
$$;

CREATE OR REPLACE FUNCTION api_eliminar_receta(p_id_receta int) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM recetas WHERE id_receta=p_id_receta) THEN
    RAISE EXCEPTION 'Receta no encontrada.' USING ERRCODE='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM registro_consumo WHERE id_receta=p_id_receta) THEN
    UPDATE recetas SET activo=false WHERE id_receta=p_id_receta;
    RETURN jsonb_build_object('action','paused','message','La receta tiene consumos registrados; fue pausada para conservar el historial.');
  END IF;
  DELETE FROM recetas WHERE id_receta=p_id_receta;
  RETURN jsonb_build_object('action','deleted','message','Receta eliminada.');
END;
$$;

CREATE OR REPLACE FUNCTION api_catalogo_recetas() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.nombre), '[]'::jsonb)
  FROM (
    SELECT r.id_receta,r.nombre,r.tipo_comida,r.calorias_estimadas,r.activo,
      COALESCE((SELECT jsonb_agg(rp.dia_semana ORDER BY rp.dia_semana) FROM receta_programacion rp WHERE rp.id_receta=r.id_receta),'[]'::jsonb) dias,
      COALESCE((SELECT jsonb_agg(jsonb_build_object('id_ingrediente',i.id_ingrediente,'nombre',i.nombre,'unidad_medida',i.unidad_medida,'cantidad_requerida',d.cantidad_requerida) ORDER BY i.nombre) FROM detalle_receta d JOIN ingredientes i USING(id_ingrediente) WHERE d.id_receta=r.id_receta),'[]'::jsonb) ingredientes
    FROM recetas r
  ) x;
$$;

CREATE OR REPLACE FUNCTION api_menu_diario(p_dia text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object('dia',p_dia,'id_receta',r.id_receta,'nombre',r.nombre,'calorias_estimadas',r.calorias_estimadas,
    'ingredientes',COALESCE(jsonb_agg(jsonb_build_object('nombre',i.nombre,'cantidad',d.cantidad_requerida,'unidad_medida',i.unidad_medida,'stock_disponible',COALESCE(inv.disponible,0),'stock_despues',GREATEST(COALESCE(inv.disponible,0)-d.cantidad_requerida,0),'faltante',GREATEST(d.cantidad_requerida-COALESCE(inv.disponible,0),0)) ORDER BY i.nombre) FILTER(WHERE i.id_ingrediente IS NOT NULL),'[]'::jsonb))
  FROM receta_programacion rp JOIN recetas r USING(id_receta) LEFT JOIN detalle_receta d USING(id_receta) LEFT JOIN ingredientes i USING(id_ingrediente)
  LEFT JOIN (SELECT id_ingrediente,SUM(cantidad_disponible) disponible FROM inventario GROUP BY id_ingrediente) inv USING(id_ingrediente)
  WHERE rp.dia_semana=p_dia AND r.activo GROUP BY r.id_receta,r.nombre,r.calorias_estimadas LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION api_eliminar_ingrediente(int),api_eliminar_receta(int),api_catalogo_recetas(),api_menu_diario(text) TO anon, authenticated;
