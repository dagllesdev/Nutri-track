# Modelo entidad-relación

El archivo [`../db/init.sql`](../db/init.sql) implementa este modelo inicial. `INVENTARIO` representa lotes: el mismo ingrediente puede tener existencias separadas por ubicación y estado de maduración.

```mermaid
erDiagram
    INGREDIENTE ||--o{ INVENTARIO : "se almacena en"
    INGREDIENTE ||--o{ HISTORIAL_COMPRAS : "se registra en"
    INGREDIENTE ||--o{ DETALLE_RECETA : "compone"
    RECETA ||--o{ DETALLE_RECETA : "contiene"
    RECETA ||--o{ REGISTRO_CONSUMO : "se consume en"

    INGREDIENTE {
        int id_ingrediente PK
        string nombre
        string categoria
        string unidad_medida
        decimal stock_minimo_alerta
        string presentacion_compra
        string dias_ingesta_abreviado
    }
    INVENTARIO {
        int id_inventario PK
        int id_ingrediente FK
        decimal cantidad_disponible
        string ubicacion
        string estado_maduracion
        timestamp fecha_ultima_actualizacion
    }
    HISTORIAL_COMPRAS {
        int id_compra PK
        int id_ingrediente FK
        timestamp fecha_compra
        string lugar_compra
        string presentacion_marca
        decimal precio_pagado_total
        decimal cantidad_comprada
        decimal costo_unitario_calculado
    }
    RECETA {
        int id_receta PK
        string nombre
        string tipo_comida
        int calorias_estimadas
    }
    DETALLE_RECETA {
        int id_detalle PK
        int id_receta FK
        int id_ingrediente FK
        decimal cantidad_requerida
    }
    REGISTRO_CONSUMO {
        int id_consumo PK
        int id_receta FK
        timestamp fecha_hora
        decimal porciones_consumidas
    }
```

## Reglas implementadas

- `HISTORIAL_COMPRAS.costo_unitario_calculado` es una columna generada por PostgreSQL.
- `DETALLE_RECETA` es la entidad asociativa que resuelve la relación muchos-a-muchos entre recetas e ingredientes.
- El consumo y la confirmación de compras ocurren dentro de transacciones SQL; el consumo rechaza operaciones que dejarían stock negativo.
- La combinación `id_ingrediente`, `ubicacion` y `estado_maduracion` identifica un lote lógico de inventario.
