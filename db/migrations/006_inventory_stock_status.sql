ALTER TABLE inventario ADD COLUMN IF NOT EXISTS estado_stock VARCHAR(20) NOT NULL DEFAULT 'OK' CHECK (estado_stock IN ('OK','REABASTECER'));

UPDATE inventario inv SET estado_stock=CASE
  WHEN (SELECT COALESCE(SUM(cantidad_disponible),0) FROM inventario WHERE id_ingrediente=inv.id_ingrediente) <=
       (SELECT stock_minimo_alerta FROM ingredientes WHERE id_ingrediente=inv.id_ingrediente)
  THEN 'REABASTECER' ELSE 'OK' END;
