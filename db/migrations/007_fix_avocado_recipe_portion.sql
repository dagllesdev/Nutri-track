-- Aguacate Hass se controla en UNIDADES: medio aguacate por sándwich.
UPDATE detalle_receta d
SET cantidad_requerida=0.50
FROM recetas r, ingredientes i
WHERE d.id_receta=r.id_receta
  AND d.id_ingrediente=i.id_ingrediente
  AND r.nombre='Sándwich Potenciado (Vie, Lun)'
  AND i.nombre='Aguacate Hass';
