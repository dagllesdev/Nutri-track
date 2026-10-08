import express from 'express';
import { pool, transaction } from './db.js';

const app = express();
app.use(express.json({ limit: '500kb' }));
app.use(express.static('public'));
const positive = (value) => Number.isFinite(Number(value)) && Number(value) > 0;

app.get('/health', async (_req, res) => {
  try { await pool.query('SELECT 1'); res.json({ status: 'ok' }); } catch { res.status(503).json({ status: 'database_unavailable' }); }
});

app.get('/api/ingredientes/capturador', async (_req, res, next) => {
  try {
    const { rows } = await pool.query(`SELECT i.id_ingrediente, i.nombre, i.categoria, i.unidad_medida, i.presentacion_compra, i.dias_ingesta_abreviado, i.stock_minimo_alerta, i.lugar_compra_predeterminado, i.cantidad_compra_estandar, i.stock_objetivo_full, inv.cantidad_disponible, GREATEST(i.stock_objetivo_full-inv.cantidad_disponible,0) cantidad_a_comprar, ultimo.costo_unitario_calculado ultimo_precio_unitario
      FROM ingredientes i JOIN LATERAL (SELECT COALESCE(SUM(cantidad_disponible),0) cantidad_disponible FROM inventario WHERE id_ingrediente=i.id_ingrediente) inv ON true
      LEFT JOIN LATERAL (SELECT costo_unitario_calculado FROM historial_compras WHERE id_ingrediente=i.id_ingrediente ORDER BY fecha_compra DESC,id_compra DESC LIMIT 1) ultimo ON true ORDER BY i.categoria, i.nombre`);
    res.json(rows);
  } catch (error) { next(error); }
});

app.get('/api/dashboard', async (_req, res, next) => {
  try {
    const { rows } = await pool.query(`SELECT i.nombre, i.unidad_medida, i.stock_minimo_alerta, SUM(inv.cantidad_disponible) cantidad_disponible,
      CASE WHEN SUM(inv.cantidad_disponible) <= i.stock_minimo_alerta THEN 'REABASTECER' ELSE 'OK' END estado
      FROM ingredientes i JOIN inventario inv USING(id_ingrediente) GROUP BY i.id_ingrediente ORDER BY estado DESC, i.nombre`);
    res.json(rows);
  } catch (error) { next(error); }
});

app.post('/api/planificador', async (req, res, next) => {
  const dia = String(req.body?.dia || '').trim();
  const nombres = { Lunes: 'Sándwich Potenciado (Vie, Lun)', Martes: 'Shake de Alta Densidad (Mar, Jue)', Miércoles: 'Tazón de Yogur & Granola (Dom, Mier)', Jueves: 'Shake de Alta Densidad (Mar, Jue)', Viernes: 'Sándwich Potenciado (Vie, Lun)', Sábado: 'Arepa Tradicional Proteica (Sab)', Domingo: 'Tazón de Yogur & Granola (Dom, Mier)' };
  if (!nombres[dia]) return res.status(400).json({ error: 'Día inválido.' });
  try {
    const { rows } = await pool.query(`SELECT r.id_receta,r.nombre,r.calorias_estimadas,COALESCE(json_agg(json_build_object('nombre',i.nombre,'cantidad',d.cantidad_requerida,'unidad_medida',i.unidad_medida,'dias_ingesta_abreviado',i.dias_ingesta_abreviado,'categoria',i.categoria,'stock_disponible',COALESCE(inv.disponible,0),'stock_despues',GREATEST(COALESCE(inv.disponible,0)-d.cantidad_requerida,0),'faltante',GREATEST(d.cantidad_requerida-COALESCE(inv.disponible,0),0)) ORDER BY i.nombre) FILTER (WHERE i.id_ingrediente IS NOT NULL),'[]') ingredientes
      FROM recetas r LEFT JOIN detalle_receta d USING(id_receta) LEFT JOIN ingredientes i USING(id_ingrediente) LEFT JOIN (SELECT id_ingrediente,SUM(cantidad_disponible) disponible FROM inventario GROUP BY id_ingrediente) inv USING(id_ingrediente) WHERE r.nombre=$1 GROUP BY r.id_receta`, [nombres[dia]]);
    if (!rows.length) return res.status(404).json({ error: 'No hay receta programada para este día.' });
    res.json({ dia, ...rows[0] });
  } catch (error) { next(error); }
});

app.post('/api/historial', async (_req, res, next) => {
  try {
    const { rows } = await pool.query(`SELECT fecha_compra,COUNT(*) cantidad_items,SUM(precio_pagado_total) total,
      json_agg(json_build_object('nombre',nombre,'lugar_compra',lugar_compra,'precio_pagado_total',precio_pagado_total,'cantidad_comprada',cantidad_comprada,'costo_unitario',costo_unitario_calculado,'unidad_medida',unidad_medida) ORDER BY nombre) compras
      FROM (SELECT h.*,i.nombre,i.unidad_medida FROM historial_compras h JOIN ingredientes i USING(id_ingrediente)) data
      GROUP BY fecha_compra ORDER BY fecha_compra DESC LIMIT 50`);
    res.json(rows);
  } catch (error) { next(error); }
});

app.post('/api/analitica', async (req, res, next) => {
  const id = Number(req.body?.id_ingrediente) || null;
  try {
    const ingredients = await pool.query('SELECT id_ingrediente,nombre FROM ingredientes ORDER BY nombre');
    const points = id ? await pool.query(`SELECT fecha_compra,costo_unitario_calculado,precio_pagado_total,cantidad_comprada,
      costo_unitario_calculado-LAG(costo_unitario_calculado) OVER(ORDER BY fecha_compra,id_compra) variacion FROM historial_compras WHERE id_ingrediente=$1 ORDER BY fecha_compra,id_compra`, [id]) : { rows: [] };
    res.json({ ingredientes: ingredients.rows, puntos: points.rows });
  } catch (error) { next(error); }
});

app.post('/api/compras/confirmar', async (req, res, next) => {
  const { compras, fecha_hora } = req.body ?? {};
  if (!Array.isArray(compras) || compras.length === 0) return res.status(400).json({ error: 'Incluya al menos una compra.' });
  if (compras.some(c => !Number.isInteger(Number(c.id_ingrediente)) || !positive(c.precio_pagado_total) || !positive(c.cantidad_comprada) || !String(c.lugar_compra || '').trim())) return res.status(400).json({ error: 'Cada compra requiere ingrediente, lugar, precio y cantidad válidos.' });
  try {
    const result = await transaction(async client => {
      const details = [];
      for (const compra of compras) {
        const ingredient = await client.query('SELECT id_ingrediente, nombre FROM ingredientes WHERE id_ingrediente=$1 FOR UPDATE', [compra.id_ingrediente]);
        if (!ingredient.rowCount) throw Object.assign(new Error('Ingrediente inválido.'), { status: 400 });
        const previous = await client.query('SELECT costo_unitario_calculado FROM historial_compras WHERE id_ingrediente=$1 ORDER BY fecha_compra DESC, id_compra DESC LIMIT 1', [compra.id_ingrediente]);
        const insert = await client.query(`INSERT INTO historial_compras (id_ingrediente,fecha_compra,lugar_compra,presentacion_marca,precio_pagado_total,cantidad_comprada)
          VALUES ($1,COALESCE($2::timestamptz,NOW()),$3,$4,$5,$6) RETURNING id_compra,costo_unitario_calculado`, [compra.id_ingrediente, fecha_hora || null, compra.lugar_compra.trim(), compra.presentacion_marca?.trim() || null, compra.precio_pagado_total, compra.cantidad_comprada]);
        const inventory = await client.query(`SELECT id_inventario, ubicacion, estado_maduracion FROM inventario WHERE id_ingrediente=$1 ORDER BY fecha_ultima_actualizacion DESC LIMIT 1 FOR UPDATE`, [compra.id_ingrediente]);
        const ubicacion = compra.ubicacion || inventory.rows[0]?.ubicacion || 'ALACENA';
        const maduracion = compra.estado_maduracion || inventory.rows[0]?.estado_maduracion || 'N_A';
        await client.query(`INSERT INTO inventario (id_ingrediente,cantidad_disponible,ubicacion,estado_maduracion) VALUES($1,$2,$3,$4)
          ON CONFLICT (id_ingrediente,ubicacion,estado_maduracion) DO UPDATE SET cantidad_disponible=inventario.cantidad_disponible+EXCLUDED.cantidad_disponible, fecha_ultima_actualizacion=NOW()`, [compra.id_ingrediente, compra.cantidad_comprada, ubicacion, maduracion]);
        const current = Number(insert.rows[0].costo_unitario_calculado); const old = previous.rowCount ? Number(previous.rows[0].costo_unitario_calculado) : null;
        details.push({ ingrediente: ingredient.rows[0].nombre, id_compra: insert.rows[0].id_compra, costo_unitario: current, variacion_porcentaje: old ? Number((((current - old) / old) * 100).toFixed(2)) : null });
      }
      return details;
    });
    res.status(201).json({ message: 'Compra confirmada e inventario actualizado.', compras: result });
  } catch (error) { next(error); }
});

app.post('/api/consumo/registrar', async (req, res, next) => {
  const { id_receta, porciones_consumidas = 1, fecha_hora } = req.body ?? {};
  if (!Number.isInteger(Number(id_receta)) || !positive(porciones_consumidas)) return res.status(400).json({ error: 'Receta y porciones válidas son obligatorias.' });
  try {
    await transaction(async client => {
      const recipe = await client.query('SELECT id_receta FROM recetas WHERE id_receta=$1', [id_receta]); if (!recipe.rowCount) throw Object.assign(new Error('Receta no encontrada.'), { status: 404 });
      const needs = await client.query('SELECT id_ingrediente, cantidad_requerida*$2 cantidad FROM detalle_receta WHERE id_receta=$1', [id_receta, porciones_consumidas]);
      for (const need of needs.rows) {
        const lots = await client.query('SELECT id_inventario, cantidad_disponible FROM inventario WHERE id_ingrediente=$1 AND cantidad_disponible > 0 ORDER BY fecha_ultima_actualizacion ASC FOR UPDATE', [need.id_ingrediente]);
        let remaining = Number(need.cantidad);
        for (const lot of lots.rows) {
          const deducted = Math.min(remaining, Number(lot.cantidad_disponible));
          await client.query('UPDATE inventario SET cantidad_disponible=cantidad_disponible-$1, fecha_ultima_actualizacion=NOW() WHERE id_inventario=$2', [deducted, lot.id_inventario]);
          remaining -= deducted;
          if (remaining <= 0) break;
        }
        if (remaining > 0) throw Object.assign(new Error('Stock insuficiente para registrar el consumo.'), { status: 409 });
      }
      await client.query('INSERT INTO registro_consumo(id_receta,fecha_hora,porciones_consumidas) VALUES($1,COALESCE($2::timestamptz,NOW()),$3)', [id_receta, fecha_hora || null, porciones_consumidas]);
      await client.query(`UPDATE inventario inv SET estado_stock=CASE WHEN resumen.cantidad<=i.stock_minimo_alerta THEN 'REABASTECER' ELSE 'OK' END
        FROM ingredientes i JOIN (SELECT id_ingrediente,SUM(cantidad_disponible) cantidad FROM inventario GROUP BY id_ingrediente) resumen ON resumen.id_ingrediente=i.id_ingrediente
        WHERE inv.id_ingrediente=i.id_ingrediente`);
    });
    const { rows } = await pool.query(`SELECT i.nombre,CASE WHEN SUM(inv.cantidad_disponible)<=i.stock_minimo_alerta THEN 'REABASTECER' ELSE 'OK' END estado
      FROM ingredientes i JOIN inventario inv USING(id_ingrediente) GROUP BY i.id_ingrediente ORDER BY i.nombre`);
    res.status(201).json({ message: 'Desayuno registrado y stock descontado con éxito.', inventario: rows });
  } catch (error) { next(error); }
});
app.use((error, _req, res, _next) => { console.error(error); res.status(error.status || 500).json({ error: error.status ? error.message : 'Error interno del servidor.' }); });
app.listen(process.env.PORT || 3000, () => console.log('NutriTrack API listening'));
