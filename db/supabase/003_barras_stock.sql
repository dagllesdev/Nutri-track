-- Ejecutar después de 002_costos_unitarios_por_sesion.sql.
CREATE OR REPLACE FUNCTION api_dashboard_inventario() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(data) ORDER BY data.estado DESC, data.nombre), '[]'::jsonb)
  FROM (
    SELECT i.nombre, i.categoria, i.unidad_medida, i.stock_minimo_alerta,
      i.stock_objetivo_full, SUM(inv.cantidad_disponible) AS cantidad_disponible,
      GREATEST(i.stock_objetivo_full - SUM(inv.cantidad_disponible), 0) AS falta_comprar,
      CASE WHEN SUM(inv.cantidad_disponible) <= i.stock_minimo_alerta THEN 'REABASTECER' ELSE 'OK' END AS estado
    FROM ingredientes i JOIN inventario inv USING(id_ingrediente)
    GROUP BY i.id_ingrediente
  ) data;
$$;

GRANT EXECUTE ON FUNCTION api_dashboard_inventario() TO anon, authenticated;
