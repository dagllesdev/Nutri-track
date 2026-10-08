-- ATENCIÓN: reemplaza catálogo, inventario, compras y consumos de prueba.
-- Úselo antes de registrar compras reales.
BEGIN;

ALTER TABLE ingredientes ADD COLUMN IF NOT EXISTS lugar_compra_predeterminado VARCHAR(100) NOT NULL DEFAULT 'Bloque 11 - Mayorista';
ALTER TABLE ingredientes ADD COLUMN IF NOT EXISTS cantidad_compra_estandar DECIMAL(10,2) NOT NULL DEFAULT 1 CHECK (cantidad_compra_estandar > 0);

DELETE FROM registro_consumo;
DELETE FROM detalle_receta;
DELETE FROM recetas;
DELETE FROM ingredientes;

INSERT INTO ingredientes (nombre,categoria,unidad_medida,stock_minimo_alerta,presentacion_compra,dias_ingesta_abreviado,lugar_compra_predeterminado,cantidad_compra_estandar) VALUES
  ('Aguacate Hass','FRESCOR','UNIDADES',1.00,'Malla x 4 un','Vie, Lun','Bloque 11 - Mayorista',4),
  ('Banano Urabá','FRESCOR','UNIDADES',2.00,'Racimo x 8 un','Diario','Bloque 11 - Mayorista',8),
  ('Huevos AA','PROTEINA','UNIDADES',6.00,'Cubeta x 30 un','Vie, Sab, Lun','Bloque 11 - Mayorista',30),
  ('Queso Campesino','LACTEOS','GRAMOS',100.00,'Bloque x 500g','Vie, Sab, Lun','Bloque 11 - Mayorista',500),
  ('Pan de Molde / Masa Madre','SECOS','UNIDADES',2.00,'Paquete x 12 rebanadas','Vie, Lun','Graneros',12),
  ('Arepas de Maíz','SECOS','UNIDADES',2.00,'Paquete x 10 un','Sab','Graneros',10),
  ('Yogur Griego Entero','LACTEOS','GRAMOS',200.00,'Tarro x 800g','Dom, Mier','Graneros',800),
  ('Avena en Hojuelas','SECOS','GRAMOS',100.00,'Bolsa x 500g','Mar, Jue','Graneros',500),
  ('Granola Artesanal','SECOS','GRAMOS',100.00,'Bolsa x 500g','Dom, Mier','Graneros',500),
  ('Mantequilla de Maní 100%','SECOS','GRAMOS',50.00,'Frasco x 350g','Mar, Jue, Dom','Graneros',350),
  ('Frutos Secos / Maní','SECOS','GRAMOS',50.00,'Bolsa x 250g','Dom, Mier','Graneros',250),
  ('Miel de Abejas','SECOS','GRAMOS',30.00,'Frasco x 250g','Dom, Mier','Graneros',250),
  ('Leche Entera','LACTEOS','MILILITROS',300.00,'Bolsón x 1000ml','Mar, Jue','Bloque 11 - Mayorista',1000);

INSERT INTO inventario (id_ingrediente,cantidad_disponible,ubicacion,estado_maduracion)
SELECT id_ingrediente,0.00,CASE WHEN categoria IN ('FRESCOR','LACTEOS') THEN 'NEVERA' ELSE 'ALACENA' END,'N_A' FROM ingredientes;

INSERT INTO recetas (nombre,tipo_comida,calorias_estimadas) VALUES
  ('Sándwich Potenciado (Vie, Lun)','DESAYUNO',750),
  ('Arepa Tradicional Proteica (Sab)','DESAYUNO',650),
  ('Tazón de Yogur & Granola (Dom, Mier)','DESAYUNO',700),
  ('Shake de Alta Densidad (Mar, Jue)','DESAYUNO',780);

INSERT INTO detalle_receta (id_receta,id_ingrediente,cantidad_requerida)
SELECT r.id_receta,i.id_ingrediente,d.cantidad
FROM (VALUES
  ('Sándwich Potenciado (Vie, Lun)','Huevos AA',3.00),('Sándwich Potenciado (Vie, Lun)','Aguacate Hass',0.50),('Sándwich Potenciado (Vie, Lun)','Queso Campesino',50.00),('Sándwich Potenciado (Vie, Lun)','Pan de Molde / Masa Madre',2.00),
  ('Arepa Tradicional Proteica (Sab)','Huevos AA',3.00),('Arepa Tradicional Proteica (Sab)','Queso Campesino',50.00),('Arepa Tradicional Proteica (Sab)','Arepas de Maíz',1.50),('Arepa Tradicional Proteica (Sab)','Banano Urabá',1.00),
  ('Tazón de Yogur & Granola (Dom, Mier)','Yogur Griego Entero',200.00),('Tazón de Yogur & Granola (Dom, Mier)','Granola Artesanal',50.00),('Tazón de Yogur & Granola (Dom, Mier)','Banano Urabá',1.00),('Tazón de Yogur & Granola (Dom, Mier)','Mantequilla de Maní 100%',30.00),('Tazón de Yogur & Granola (Dom, Mier)','Frutos Secos / Maní',20.00),('Tazón de Yogur & Granola (Dom, Mier)','Miel de Abejas',15.00),
  ('Shake de Alta Densidad (Mar, Jue)','Leche Entera',300.00),('Shake de Alta Densidad (Mar, Jue)','Avena en Hojuelas',50.00),('Shake de Alta Densidad (Mar, Jue)','Banano Urabá',1.00),('Shake de Alta Densidad (Mar, Jue)','Mantequilla de Maní 100%',30.00)
) AS d(nombre_receta,nombre_ingrediente,cantidad)
JOIN recetas r ON r.nombre=d.nombre_receta JOIN ingredientes i ON i.nombre=d.nombre_ingrediente;

COMMIT;
