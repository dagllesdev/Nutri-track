ALTER TABLE ingredientes ADD COLUMN IF NOT EXISTS stock_objetivo_full DECIMAL(10,2) NOT NULL DEFAULT 1 CHECK (stock_objetivo_full >= 0);

UPDATE ingredientes SET stock_objetivo_full=cantidad_compra_estandar;

-- Metas de inventario para cubrir el ciclo completo de desayunos.
UPDATE ingredientes SET stock_objetivo_full=4 WHERE nombre='Aguacate Hass';
UPDATE ingredientes SET stock_objetivo_full=8 WHERE nombre='Banano Urabá';
UPDATE ingredientes SET stock_objetivo_full=30 WHERE nombre='Huevos AA';
UPDATE ingredientes SET stock_objetivo_full=500 WHERE nombre='Queso Campesino';
UPDATE ingredientes SET stock_objetivo_full=12 WHERE nombre='Pan de Molde / Masa Madre';
UPDATE ingredientes SET stock_objetivo_full=10 WHERE nombre='Arepas de Maíz';
UPDATE ingredientes SET stock_objetivo_full=800 WHERE nombre='Yogur Griego Entero';
UPDATE ingredientes SET stock_objetivo_full=500 WHERE nombre IN ('Avena en Hojuelas','Granola Artesanal');
UPDATE ingredientes SET stock_objetivo_full=350 WHERE nombre='Mantequilla de Maní 100%';
UPDATE ingredientes SET stock_objetivo_full=250 WHERE nombre IN ('Frutos Secos / Maní','Miel de Abejas');
UPDATE ingredientes SET stock_objetivo_full=1000 WHERE nombre='Leche Entera';
