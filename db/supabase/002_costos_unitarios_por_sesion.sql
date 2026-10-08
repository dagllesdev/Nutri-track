-- Ejecutar después de 001_pages_rpc.sql en el SQL Editor de Supabase.
-- La comparación es por costo unitario ponderado de la sesión, nunca por total pagado.

CREATE OR REPLACE FUNCTION api_historial_compras() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  WITH compras AS (
    SELECT h.*, i.nombre, i.unidad_medida, i.presentacion_compra
    FROM historial_compras h JOIN ingredientes i USING(id_ingrediente)
  ), costos_sesion AS (
    SELECT fecha_compra, id_ingrediente,
      SUM(precio_pagado_total) / NULLIF(SUM(cantidad_comprada), 0) AS costo_unitario_sesion
    FROM compras GROUP BY fecha_compra, id_ingrediente
  ), costos_con_tendencia AS (
    SELECT *, LAG(costo_unitario_sesion) OVER (
      PARTITION BY id_ingrediente ORDER BY fecha_compra
    ) AS costo_unitario_anterior
    FROM costos_sesion
  ), sesiones AS (
    SELECT fecha_compra, COUNT(*) AS cantidad_items, SUM(precio_pagado_total) AS total
    FROM compras GROUP BY fecha_compra
  ), sesiones_con_tendencia AS (
    SELECT *, total - LAG(total) OVER (ORDER BY fecha_compra) AS variacion_total,
      LAG(total) OVER (ORDER BY fecha_compra) AS total_anterior
    FROM sesiones
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(data) ORDER BY data.fecha_compra DESC), '[]'::jsonb)
  FROM (
    SELECT s.fecha_compra, s.cantidad_items, s.total, s.variacion_total,
      CASE WHEN s.total_anterior IS NULL OR s.total_anterior = 0 THEN NULL
           ELSE ROUND((s.variacion_total / s.total_anterior) * 100, 2) END AS variacion_porcentaje,
      jsonb_agg(jsonb_build_object(
        'nombre', c.nombre,
        'lugar_compra', c.lugar_compra,
        'presentacion', COALESCE(c.presentacion_marca, c.presentacion_compra),
        'precio_pagado_total', c.precio_pagado_total,
        -- Compatibilidad temporal con el badge del frontend: la resta contra
        -- este valor siempre equivale al delta unitario de sesión.
        'precio_anterior', CASE WHEN t.costo_unitario_anterior IS NULL THEN NULL
          ELSE c.precio_pagado_total - (t.costo_unitario_sesion - t.costo_unitario_anterior) END,
        'cantidad_comprada', c.cantidad_comprada,
        'costo_unitario', c.costo_unitario_calculado,
        'costo_unitario_sesion', t.costo_unitario_sesion,
        'costo_unitario_anterior', t.costo_unitario_anterior,
        'delta_unitario', t.costo_unitario_sesion - t.costo_unitario_anterior,
        'unidad_medida', c.unidad_medida
      ) ORDER BY c.nombre, c.id_compra) AS compras
    FROM sesiones_con_tendencia s
    JOIN compras c USING(fecha_compra)
    JOIN costos_con_tendencia t USING(fecha_compra, id_ingrediente)
    GROUP BY s.fecha_compra, s.cantidad_items, s.total, s.variacion_total, s.total_anterior
    ORDER BY s.fecha_compra DESC LIMIT 50
  ) data;
$$;

CREATE OR REPLACE FUNCTION api_analitica_precios(p_id_ingrediente integer DEFAULT NULL) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  WITH costos_sesion AS (
    SELECT fecha_compra,
      SUM(precio_pagado_total) / NULLIF(SUM(cantidad_comprada), 0) AS costo_unitario_calculado
    FROM historial_compras WHERE id_ingrediente = p_id_ingrediente
    GROUP BY fecha_compra
  ), puntos AS (
    SELECT fecha_compra, costo_unitario_calculado,
      costo_unitario_calculado - LAG(costo_unitario_calculado) OVER (ORDER BY fecha_compra) AS variacion
    FROM costos_sesion
  )
  SELECT jsonb_build_object(
    'ingredientes', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id_ingrediente', id_ingrediente, 'nombre', nombre) ORDER BY nombre), '[]'::jsonb) FROM ingredientes),
    'puntos', (SELECT COALESCE(jsonb_agg(to_jsonb(puntos) ORDER BY fecha_compra), '[]'::jsonb) FROM puntos)
  );
$$;

GRANT EXECUTE ON FUNCTION api_historial_compras(), api_analitica_precios(integer) TO anon, authenticated;
