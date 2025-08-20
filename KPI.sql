-- =====================================================
-- KPI DE NEGOCIO 
-- =====================================================

SELECT b.period,
    SUM(b.total) as facturado_total,               -- Facturado total
    
    SUM(CASE 
        WHEN p.paid_at <= DATE_ADD(b.cuttoff_date, INTERVAL 7 DAY)             -- Pagado en diferentes tiempos
        THEN b.total ELSE 0 
    END) as pagado_7_dias,
    
    SUM(CASE 
        WHEN p.paid_at <= DATE_ADD(b.cuttoff_date, INTERVAL 30 DAY) 
        THEN b.total ELSE 0 
    END) as pagado_30_dias,
    
    SUM(CASE 
        WHEN p.paid_at <= DATE_ADD(b.cuttoff_date, INTERVAL 60 DAY) 
        THEN b.total ELSE 0 
    END) as pagado_60_dias,
    
    ROUND(
        SUM(CASE WHEN p.paid_at <= DATE_ADD(b.cuttoff_date, INTERVAL 7 DAY) THEN b.total ELSE 0 END)               -- Porcentajes de recuperacion
        / SUM(b.total) * 100, 1
    ) as recuperacion_7_dias_pct,
    
    ROUND(
        SUM(CASE WHEN p.paid_at <= DATE_ADD(b.cuttoff_date, INTERVAL 30 DAY) THEN b.total ELSE 0 END) 
        / SUM(b.total) * 100, 1
    ) as recuperacion_30_dias_pct,
    
    ROUND(
        SUM(CASE WHEN p.paid_at <= DATE_ADD(b.cuttoff_date, INTERVAL 60 DAY) THEN b.total ELSE 0 END) 
        / SUM(b.total) * 100, 1
    ) as recuperacion_60_dias_pct

FROM bills b
LEFT JOIN payments p ON b.id = p.bill_id AND p.status = 'completed'
WHERE b.status IS NOT NULL AND b.status <> ''
GROUP BY b.period
ORDER BY b.period;

-- =====================================================
-- CONTRATOS CON ANOMALIAS (>±50%) AL MENOS DOS DIAS DEL PERIODO
-- =====================================================

WITH consumo_promedio AS (
    SELECT 
        contract_id,
        AVG(kwh) as kwh_promedio
    FROM consumptions 
    WHERE deleted_at = ''
      AND kwh > 0                                                 -- Excluiyo los consumos en 0
    GROUP BY contract_id
    HAVING COUNT(*) >= 7                                -- Al menos 7 dias de datos para calcular un promedio confiable
),

dias_anomalia AS (
    SELECT 
        c.contract_id,
        DATE(c.date) as fecha,
        c.kwh,
        cp.kwh_promedio,     
        CASE                                            -- La anomalia aparece si está 50% por encima o por debajo del promedio
            WHEN cp.kwh_promedio > 0 
                 AND (c.kwh > cp.kwh_promedio * 1.5 OR c.kwh < cp.kwh_promedio * 0.5)
            THEN 1 ELSE 0 
        END as es_anomalia
    FROM consumptions c
    JOIN consumo_promedio cp ON c.contract_id = cp.contract_id
    WHERE c.deleted_at = ''
      AND c.kwh > 0
),

contratos_anomalias_periodo AS (
    SELECT 
        da.contract_id,
        b.period,
        COUNT(*) as dias_con_anomalia
    FROM dias_anomalia da
    JOIN contracts ct ON da.contract_id = ct.contract_id
    JOIN bills b ON ct.contract_id = b.contract_id
    WHERE da.es_anomalia = 1
      AND da.fecha BETWEEN DATE(b.cuttoff_date) - INTERVAL 30 DAY AND DATE(b.cuttoff_date)
    GROUP BY da.contract_id, b.period
    HAVING COUNT(*) >= 2                                       -- Las consultas con al menos 2 dias con anomalias
)

SELECT 
    period,
    COUNT(DISTINCT contract_id) as contratos_con_anomalia
FROM contratos_anomalias_periodo
GROUP BY period
ORDER BY period;

-- =====================================================
-- FACTURAS CON CONTRIBUTIONS
-- =====================================================

WITH facturas_contribution AS (
    SELECT 
        b.id as bill_id,
        b.contract_id,
        b.period,
        b.cuttoff_date,
        -- Verificar si tiene contribution
        EXISTS(
            SELECT 1 FROM bill_details bd 
            WHERE bd.bill_id = b.id 
              AND bd.line_type = 'contribution'
        ) as tiene_contribution
    FROM bills b
),

facturas_ordenadas AS (
    SELECT 
        *,
        -- Factura anterior del mismo contrato
        LAG(tiene_contribution) OVER (
            PARTITION BY contract_id 
            ORDER BY cuttoff_date
        ) as contribution_factura_anterior
    FROM facturas_contribution
)

SELECT 
    period,
    COUNT(*) as facturas_nuevas_contribution
FROM facturas_ordenadas
WHERE tiene_contribution = 1  -- Factura actual tiene contribution
  AND (contribution_factura_anterior = 0 OR contribution_factura_anterior IS NULL)  -- No tenia una contribution en la factura anterior
GROUP BY period
ORDER BY period;

-- =====================================================
-- CONSULTA CON TODAS LAS METRICAS
-- =====================================================

SELECT 
    kpi.period,
    kpi.facturado_total,
    kpi.pagado_7_dias,
    kpi.pagado_30_dias,
    kpi.pagado_60_dias,
    kpi.recuperacion_7_dias_pct,
    kpi.recuperacion_30_dias_pct,
    kpi.recuperacion_60_dias_pct,
    COALESCE(anomalias.contratos_con_anomalia, 0) as contratos_con_anomalia,
    COALESCE(nuevas_contrib.facturas_nuevas_contribution, 0) as facturas_nuevas_contribution
    
FROM (
    -- KPI principal con facturacion y recuperacion
    SELECT 
        b.period,
        SUM(b.total) as facturado_total,
        SUM(CASE WHEN p.paid_at <= DATE_ADD(b.cuttoff_date, INTERVAL 7 DAY) THEN b.total ELSE 0 END) as pagado_7_dias,
        SUM(CASE WHEN p.paid_at <= DATE_ADD(b.cuttoff_date, INTERVAL 30 DAY) THEN b.total ELSE 0 END) as pagado_30_dias,
        SUM(CASE WHEN p.paid_at <= DATE_ADD(b.cuttoff_date, INTERVAL 60 DAY) THEN b.total ELSE 0 END) as pagado_60_dias,
        ROUND(SUM(CASE WHEN p.paid_at <= DATE_ADD(b.cuttoff_date, INTERVAL 7 DAY) THEN b.total ELSE 0 END) / SUM(b.total) * 100, 1) as recuperacion_7_dias_pct,
        ROUND(SUM(CASE WHEN p.paid_at <= DATE_ADD(b.cuttoff_date, INTERVAL 30 DAY) THEN b.total ELSE 0 END) / SUM(b.total) * 100, 1) as recuperacion_30_dias_pct,
        ROUND(SUM(CASE WHEN p.paid_at <= DATE_ADD(b.cuttoff_date, INTERVAL 60 DAY) THEN b.total ELSE 0 END) / SUM(b.total) * 100, 1) as recuperacion_60_dias_pct
    FROM bills b
    LEFT JOIN payments p ON b.id = p.bill_id AND p.status = 'completed'
    WHERE b.status IS NOT NULL AND b.status <> ''
    GROUP BY b.period
) kpi

LEFT JOIN (
    -- Subquery de anomalias (usar la consulta auxiliar 1 completa)
    WITH consumo_promedio AS (
        SELECT contract_id, AVG(kwh) as kwh_promedio
        FROM consumptions 
        WHERE deleted_at = '' AND kwh > 0
        GROUP BY contract_id
        HAVING COUNT(*) >= 7
    ),
    dias_anomalia AS (
        SELECT c.contract_id, DATE(c.date) as fecha, c.kwh, cp.kwh_promedio,
               CASE WHEN cp.kwh_promedio > 0 AND (c.kwh > cp.kwh_promedio * 1.5 OR c.kwh < cp.kwh_promedio * 0.5) THEN 1 ELSE 0 END as es_anomalia
        FROM consumptions c
        JOIN consumo_promedio cp ON c.contract_id = cp.contract_id
        WHERE c.deleted_at = '' AND c.kwh > 0
    ),
    contratos_anomalias_periodo AS (
        SELECT da.contract_id, b.period, COUNT(*) as dias_con_anomalia
        FROM dias_anomalia da
        JOIN contracts ct ON da.contract_id = ct.contract_id
        JOIN bills b ON ct.contract_id = b.contract_id
        WHERE da.es_anomalia = 1 AND da.fecha BETWEEN DATE(b.cuttoff_date) - INTERVAL 30 DAY AND DATE(b.cuttoff_date)
        GROUP BY da.contract_id, b.period
        HAVING COUNT(*) >= 2
    )
    SELECT period, COUNT(DISTINCT contract_id) as contratos_con_anomalia
    FROM contratos_anomalias_periodo
    GROUP BY period
) anomalias ON kpi.period = anomalias.period

LEFT JOIN (
    -- Subquery de nuevas contributions (usar la consulta auxiliar 2 completa)
    WITH facturas_contribution AS (
        SELECT b.id as bill_id, b.contract_id, b.period, b.cuttoff_date,
               EXISTS(SELECT 1 FROM bill_details bd WHERE bd.bill_id = b.id AND bd.line_type = 'contribution') as tiene_contribution
        FROM bills b
    ),
    facturas_ordenadas AS (
        SELECT *, LAG(tiene_contribution) OVER (PARTITION BY contract_id ORDER BY cuttoff_date) as contribution_factura_anterior
        FROM facturas_contribution
    )
    SELECT period, COUNT(*) as facturas_nuevas_contribution
    FROM facturas_ordenadas
    WHERE tiene_contribution = 1 AND (contribution_factura_anterior = 0 OR contribution_factura_anterior IS NULL)
    GROUP BY period
) nuevas_contrib ON kpi.period = nuevas_contrib.period

ORDER BY kpi.period;