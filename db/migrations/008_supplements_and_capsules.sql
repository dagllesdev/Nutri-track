ALTER TABLE ingredientes DROP CONSTRAINT IF EXISTS ingredientes_unidad_medida_check;
ALTER TABLE ingredientes ADD CONSTRAINT ingredientes_unidad_medida_check CHECK (unidad_medida IN ('GRAMOS','MILILITROS','UNIDADES','CAPSULAS'));

INSERT INTO ingredientes (nombre,categoria,unidad_medida,stock_minimo_alerta,presentacion_compra,dias_ingesta_abreviado,lugar_compra_predeterminado,cantidad_compra_estandar,stock_objetivo_full)
VALUES
  ('Omega-3 (IFOS Ultra Pure)','SUPLEMENTOS','CAPSULAS',14,'Tarro x 60 softgels','DIARIO','Tienda Naturista / Droguería',60,60),
  ('Glicinato de Magnesio','SUPLEMENTOS','CAPSULAS',10,'Tarro x 90 caps','DIARIO','Tienda Naturista / Droguería',90,90)
ON CONFLICT (nombre) DO UPDATE SET categoria=EXCLUDED.categoria,unidad_medida=EXCLUDED.unidad_medida,stock_minimo_alerta=EXCLUDED.stock_minimo_alerta,presentacion_compra=EXCLUDED.presentacion_compra,dias_ingesta_abreviado=EXCLUDED.dias_ingesta_abreviado,lugar_compra_predeterminado=EXCLUDED.lugar_compra_predeterminado,cantidad_compra_estandar=EXCLUDED.cantidad_compra_estandar,stock_objetivo_full=EXCLUDED.stock_objetivo_full;

INSERT INTO inventario (id_ingrediente,cantidad_disponible,ubicacion,estado_maduracion,estado_stock)
SELECT id_ingrediente,0,'ALACENA','N_A','REABASTECER' FROM ingredientes WHERE categoria='SUPLEMENTOS'
ON CONFLICT (id_ingrediente,ubicacion,estado_maduracion) DO NOTHING;
