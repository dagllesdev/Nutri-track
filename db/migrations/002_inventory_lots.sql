-- Aplicar solo en instalaciones que ya ejecutaron db/init.sql con la restricción anterior.
ALTER TABLE inventario DROP CONSTRAINT IF EXISTS inventario_id_ingrediente_ubicacion_key;
ALTER TABLE inventario
  ADD CONSTRAINT inventario_ingrediente_ubicacion_maduracion_key
  UNIQUE (id_ingrediente, ubicacion, estado_maduracion);
