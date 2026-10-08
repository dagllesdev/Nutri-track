ALTER TABLE ingredientes ADD COLUMN IF NOT EXISTS lugar_compra_predeterminado VARCHAR(100) NOT NULL DEFAULT 'Bloque 11 - Mayorista';
ALTER TABLE ingredientes ADD COLUMN IF NOT EXISTS cantidad_compra_estandar DECIMAL(10,2) NOT NULL DEFAULT 1 CHECK (cantidad_compra_estandar > 0);

UPDATE ingredientes SET lugar_compra_predeterminado='Graneros', cantidad_compra_estandar=1000 WHERE nombre IN ('Avena','Yogur griego');
UPDATE ingredientes SET lugar_compra_predeterminado='Graneros', cantidad_compra_estandar=2500 WHERE nombre='Arroz';
UPDATE ingredientes SET lugar_compra_predeterminado='Graneros', cantidad_compra_estandar=900 WHERE nombre='Proteína whey';
UPDATE ingredientes SET lugar_compra_predeterminado='Graneros', cantidad_compra_estandar=300 WHERE nombre IN ('Creatina','Colágeno hidrolizado');
UPDATE ingredientes SET lugar_compra_predeterminado='Bloque 21 - Mayorista', cantidad_compra_estandar=1000 WHERE nombre='Pollo';
UPDATE ingredientes SET lugar_compra_predeterminado='Bloque 21 - Mayorista', cantidad_compra_estandar=500 WHERE nombre='Carne molida';
UPDATE ingredientes SET cantidad_compra_estandar=30 WHERE nombre='Huevos';
UPDATE ingredientes SET cantidad_compra_estandar=5 WHERE nombre='Aguacate';
UPDATE ingredientes SET cantidad_compra_estandar=5000 WHERE nombre='Papa';
