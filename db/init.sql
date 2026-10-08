CREATE TABLE ingredientes (
  id_ingrediente SERIAL PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL UNIQUE,
  categoria VARCHAR(50) NOT NULL CHECK (categoria IN ('FRESCOR','LACTEOS','PROTEINA','SECOS','SUPLEMENTOS')),
  unidad_medida VARCHAR(20) NOT NULL CHECK (unidad_medida IN ('GRAMOS','MILILITROS','UNIDADES')),
  stock_minimo_alerta DECIMAL(10,2) NOT NULL CHECK (stock_minimo_alerta >= 0),
  presentacion_compra VARCHAR(100) NOT NULL,
  dias_ingesta_abreviado VARCHAR(50) NOT NULL,
  lugar_compra_predeterminado VARCHAR(100) NOT NULL DEFAULT 'Bloque 11 - Mayorista',
  cantidad_compra_estandar DECIMAL(10,2) NOT NULL DEFAULT 1 CHECK (cantidad_compra_estandar > 0),
  stock_objetivo_full DECIMAL(10,2) NOT NULL DEFAULT 1 CHECK (stock_objetivo_full >= 0)
);

CREATE TABLE inventario (
  id_inventario SERIAL PRIMARY KEY,
  id_ingrediente INT NOT NULL REFERENCES ingredientes(id_ingrediente) ON DELETE CASCADE,
  cantidad_disponible DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (cantidad_disponible >= 0),
  ubicacion VARCHAR(50) NOT NULL CHECK (ubicacion IN ('NEVERA','CONGELADOR','ALACENA')),
  estado_maduracion VARCHAR(50) NOT NULL DEFAULT 'N_A' CHECK (estado_maduracion IN ('VERDE','PINTON','MADURO','CONGELADO','N_A')),
  fecha_ultima_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (id_ingrediente, ubicacion, estado_maduracion)
);

CREATE TABLE historial_compras (
  id_compra SERIAL PRIMARY KEY,
  id_ingrediente INT NOT NULL REFERENCES ingredientes(id_ingrediente) ON DELETE CASCADE,
  fecha_compra TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  lugar_compra VARCHAR(100) NOT NULL,
  presentacion_marca VARCHAR(100),
  precio_pagado_total DECIMAL(12,2) NOT NULL CHECK (precio_pagado_total > 0),
  cantidad_comprada DECIMAL(10,2) NOT NULL CHECK (cantidad_comprada > 0),
  costo_unitario_calculado DECIMAL(12,4) GENERATED ALWAYS AS (precio_pagado_total / cantidad_comprada) STORED
);
CREATE INDEX historial_compras_ingrediente_fecha_idx ON historial_compras(id_ingrediente, fecha_compra DESC);

CREATE TABLE recetas (
  id_receta SERIAL PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL UNIQUE,
  tipo_comida VARCHAR(30) NOT NULL CHECK (tipo_comida IN ('DESAYUNO','ALMUERZO','CENA','SNACK')),
  calorias_estimadas INT NOT NULL CHECK (calorias_estimadas >= 0)
);
CREATE TABLE detalle_receta (
  id_detalle SERIAL PRIMARY KEY,
  id_receta INT NOT NULL REFERENCES recetas(id_receta) ON DELETE CASCADE,
  id_ingrediente INT NOT NULL REFERENCES ingredientes(id_ingrediente) ON DELETE CASCADE,
  cantidad_requerida DECIMAL(10,2) NOT NULL CHECK (cantidad_requerida > 0),
  UNIQUE(id_receta, id_ingrediente)
);
CREATE TABLE registro_consumo (
  id_consumo SERIAL PRIMARY KEY,
  id_receta INT NOT NULL REFERENCES recetas(id_receta) ON DELETE RESTRICT,
  fecha_hora TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  porciones_consumidas DECIMAL(4,2) NOT NULL DEFAULT 1 CHECK (porciones_consumidas > 0)
);

INSERT INTO ingredientes (nombre,categoria,unidad_medida,stock_minimo_alerta,presentacion_compra,dias_ingesta_abreviado,lugar_compra_predeterminado,cantidad_compra_estandar) VALUES
('Huevos','PROTEINA','UNIDADES',12,'Cubeta x 30','Diario','Bloque 11 - Mayorista',30),
('Avena','SECOS','GRAMOS',500,'Bolsa x 1000 g','Diario','Graneros',1000),
('Leche','LACTEOS','MILILITROS',1000,'Bolsa x 1000 ml','Diario','Bloque 11 - Mayorista',1000),
('Banano','FRESCOR','GRAMOS',500,'Manojo','Vie, Lun','Bloque 11 - Mayorista',1000),
('Aguacate','FRESCOR','GRAMOS',300,'Unidad','Vie, Lun','Bloque 11 - Mayorista',5),
('Pollo','PROTEINA','GRAMOS',1000,'Bandeja x 1000 g','Mar, Jue','Bloque 21 - Mayorista',1000),
('Carne molida','PROTEINA','GRAMOS',500,'Bandeja x 500 g','Sab, Dom','Bloque 21 - Mayorista',500),
('Arroz','SECOS','GRAMOS',1000,'Bolsa x 2500 g','Diario','Graneros',2500),
('Papa','FRESCOR','GRAMOS',1000,'Bulto','Mar, Jue','Bloque 11 - Mayorista',5000),
('Yogur griego','LACTEOS','GRAMOS',500,'Tarro x 1000 g','Diario','Graneros',1000),
('Proteína whey','SUPLEMENTOS','GRAMOS',150,'Tarro x 900 g','Diario','Graneros',900),
('Creatina','SUPLEMENTOS','GRAMOS',50,'Tarro x 300 g','Diario','Graneros',300),
('Colágeno hidrolizado','SUPLEMENTOS','GRAMOS',100,'Bolsa x 300 g','Diario','Graneros',300);

INSERT INTO inventario (id_ingrediente, cantidad_disponible, ubicacion, estado_maduracion)
SELECT id_ingrediente, 0, CASE WHEN categoria='FRESCOR' OR categoria='LACTEOS' THEN 'NEVERA' WHEN nombre='Pollo' OR nombre='Carne molida' THEN 'CONGELADOR' ELSE 'ALACENA' END, 'N_A' FROM ingredientes;

INSERT INTO recetas(nombre,tipo_comida,calorias_estimadas) VALUES ('Desayuno base','DESAYUNO',620);
INSERT INTO detalle_receta(id_receta,id_ingrediente,cantidad_requerida)
SELECT 1,id_ingrediente,CASE nombre WHEN 'Huevos' THEN 3 WHEN 'Avena' THEN 80 WHEN 'Leche' THEN 250 WHEN 'Banano' THEN 120 WHEN 'Proteína whey' THEN 30 WHEN 'Creatina' THEN 5 ELSE 0 END FROM ingredientes WHERE nombre IN ('Huevos','Avena','Leche','Banano','Proteína whey','Creatina');
