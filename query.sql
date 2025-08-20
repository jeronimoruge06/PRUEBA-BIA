-- =====================================================
--                     PARTE A
-- =====================================================

-- =====================================================
-- 1. AGREGACIONES Y FILTROS
-- Para julio de 2024: contract_id, kWh total y kWh promedio diario
-- A la hora de verificar el delete_at no se usa el IS NULL, 
-- porque que se compara con una cadena vacia para evuitar problemas de NULLS.
-- =====================================================

SELECT contract_id,
    SUM(kwh) as kwh_total,
    ROUND(SUM(kwh) / COUNT(DISTINCT DATE(date)), 2) as kwh_promedio_diario,
    COUNT(DISTINCT DATE(date)) as dias_con_consumo,
    COUNT(*) as total_registros
FROM BIA.consumptions 
WHERE YEAR(date) = 2024 
    AND MONTH(date) = 7
    AND deleted_at = ''
GROUP BY contract_id
ORDER BY kwh_total DESC;

-- =====================================================
-- 2. WINDOW FUNCTIONS
-- Variacion % diaria de kWh vs. dia anterior y señala anomalias > +50% o < -50%
-- Se busca agregar el consumo por dia y por contrato
-- Se calcula el consumo del dia anterior usando la funcion LAG 
-- Se calcula la variacion porcentual
-- =====================================================

WITH consumo_diario AS (
    SELECT contract_id,
        DATE(date) as fecha,
        SUM(kwh) as kwh_diario
    FROM BIA.consumptions 
    WHERE deleted_at = ''
    GROUP BY contract_id, DATE(date)
),

consumo_con_anterior AS (
    SELECT contract_id,
        fecha,
        kwh_diario,
        LAG(kwh_diario, 1) OVER (
            PARTITION BY contract_id 
            ORDER BY fecha
        ) as kwh_dia_anterior
    FROM consumo_diario
),

variaciones AS (
    SELECT contract_id,
        fecha,
        kwh_diario,
        kwh_dia_anterior,
        CASE 
            WHEN kwh_dia_anterior IS NULL THEN NULL
            WHEN kwh_dia_anterior = 0 THEN 
                CASE 
                    WHEN kwh_diario > 0 THEN 999.99  -- Se concidera como una anomalia extrema
                    ELSE 0
                END
            ELSE ROUND(((kwh_diario - kwh_dia_anterior) / kwh_dia_anterior) * 100, 2)
        END as variacion_porcentual
    FROM consumo_con_anterior
)

SELECT contract_id,
    fecha,
    kwh_diario,
    kwh_dia_anterior,
    variacion_porcentual,
    CASE 
        WHEN variacion_porcentual IS NULL THEN 'Primer dia'
        WHEN variacion_porcentual > 50 THEN 'ANOMALIA ALTO (+50%+)'
        WHEN variacion_porcentual < -50 THEN 'ANOMALIA BAJO (-50%-)'
        WHEN ABS(variacion_porcentual) <= 10 THEN 'Normal'
        ELSE 'Variacion moderada'
    END as clasificacion_anomalia
FROM variaciones
ORDER BY contract_id, fecha;

-- =====================================================
-- 3. COHORTE DE FACTURAS Y RECAUDO
-- Por periodo: monto facturado, pagado y % recuperacion a 30 días
-- Monto total facturado por periodo
-- Monto total pagado por periodo, pagos realizados dentro de 30 días desde cutoff_date
-- =====================================================

WITH facturacion_por_periodo AS (
    SELECT 
        period,
        COUNT(*) as total_facturas,
        SUM(total) as monto_facturado,
        MIN(cuttoff_date) as primera_fecha_corte,
        MAX(cuttoff_date) as ultima_fecha_corte
    FROM BIA.bills 
    WHERE total IS NOT NULL
    GROUP BY period
),

pagos_por_periodo AS (
    SELECT b.period,
        COUNT(p.id) as facturas_pagadas,
        SUM(b.total) as monto_pagado,
        SUM(CASE 
            WHEN p.status = 'paid' 
            AND DATEDIFF(p.paid_at, b.cuttoff_date) <= 30 
            THEN b.total 
            ELSE 0 
        END) as monto_pagado_30_dias,
        COUNT(CASE 
            WHEN p.status = 'paid' 
            AND DATEDIFF(p.paid_at, b.cuttoff_date) <= 30 
            THEN 1 
        END) as facturas_pagadas_30_dias
    FROM BIA.bills b
    INNER JOIN BIA.payments p ON b.id = p.bill_id
    WHERE p.status = 'paid' AND b.total IS NOT NULL
    GROUP BY b.period
)

SELECT 
    fp.period,
    fp.total_facturas,
    fp.monto_facturado,
    COALESCE(pp.monto_pagado, 0) as monto_pagado_total,
    COALESCE(pp.monto_pagado_30_dias, 0) as monto_pagado_30_dias,
    COALESCE(pp.facturas_pagadas, 0) as facturas_pagadas_total,
    COALESCE(pp.facturas_pagadas_30_dias, 0) as facturas_pagadas_30_dias,

    ROUND(
        (COALESCE(pp.monto_pagado, 0) / fp.monto_facturado) * 100, 2            -- Porcentaje de recuperacion
    ) as porcentaje_recuperacion_total,
    
    ROUND(
        (COALESCE(pp.monto_pagado_30_dias, 0) / fp.monto_facturado) * 100, 2
    ) as porcentaje_recuperacion_30_dias,
    
    CASE 
        WHEN (COALESCE(pp.monto_pagado_30_dias, 0) / fp.monto_facturado) * 100 >= 90 THEN 'Perfecto'
        WHEN (COALESCE(pp.monto_pagado_30_dias, 0) / fp.monto_facturado) * 100 >= 75 THEN 'Bueno'        -- Clasificacion de la recuperacion
        WHEN (COALESCE(pp.monto_pagado_30_dias, 0) / fp.monto_facturado) * 100 >= 50 THEN 'Regular' 
        ELSE 'Malo'
    END as clasificacion_cobranza

FROM facturacion_por_periodo fp
LEFT JOIN pagos_por_periodo pp ON fp.period = pp.period
ORDER BY fp.period DESC;


-- =====================================================
-- 4. CONSULTA CON BUG EJEMPLO Y CORRECCIÓN
-- =====================================================

--  CONSULTA CON BUG : Esta consulta tiene un problemas tpico

-- SELECT contract_id,
--     SUM(kwh) as kwh_total,
--     ROUND(SUM(kwh) / COUNT(DISTINCT DATE(date)), 2) as kwh_promedio_diario,
--     COUNT(DISTINCT DATE(date)) as dias_con_consumo,
--     COUNT(*) as total_registros
-- FROM BIA.consumptions 
-- WHERE YEAR(date) = 2024 
--     AND MONTH(date) = 7
--     AND deleted_at IS NULL
-- GROUP BY contract_id
-- ORDER BY kwh_total DESC;

SELECT contract_id,
    SUM(kwh) as kwh_total,
    ROUND(SUM(kwh) / COUNT(DISTINCT DATE(date)), 2) as kwh_promedio_diario,
    COUNT(DISTINCT DATE(date)) as dias_con_consumo, 
    COUNT(*) as total_registros
FROM BIA.consumptions 
WHERE YEAR(date) = 2024 
    AND MONTH(date) = 7
    AND deleted_at = ''    -- Correccion: se usa cadena vacia para evitar problemas con NULLS
GROUP BY contract_id
ORDER BY kwh_total DESC;

-- =====================================================
-- 5. PERFORMANCE & DISEÑO - INDICES POSIBLES 
-- =====================================================

-- Para optimizar las consultas de consumos y anomalias (2):
-- CREATE INDEX idx_consumptions_contract_date_kwh ON BIA.consumptions (contract_id, date, kwh, deleted_at);
-- CREATE INDEX idx_consumptions_date_contract ON BIA.consumptions (date, contract_id) WHERE deleted_at = '';

-- Para optimizar cohortes de facturacion (3):
-- CREATE INDEX idx_bills_period_cutoff ON BIA.bills (period, cuttoff_date, total);
-- CREATE INDEX idx_payments_bill_status_date ON BIA.payments (bill_id, status, paid_at);

-- Para optimizar:
-- CREATE INDEX idx_contracts_company ON BIA.contracts (company_id, contract_id);
-- CREATE INDEX idx_bill_details_bill_amount ON BIA.bill_details (bill_id, line_type, amount);


-- =====================================================
--                     PARTE B
-- =====================================================

-- =====================================================
-- 1. KPI DE NEGOCIO - TABLA POR PERÍODO EN EL ARCHIVO KPI.sql
-- =====================================================



-- =====================================================
-- 2. DATA QUALITY CHECKS - 5 REGLAS DE CONTROL
-- =====================================================

--  REGLA 1: Integridad referencial completa

SELECT 'Integridad Referencial' as categoria,
    'Contratos huérfanos' as regla,
    COUNT(*) as registros_problematicos,
    'CRITICO' as severidad,
    GROUP_CONCAT(c.contract_id SEPARATOR '; ') as elementos_afectados
FROM BIA.contracts c
LEFT JOIN BIA.companies comp ON c.company_id = comp.company_id
WHERE comp.company_id IS NULL

UNION ALL

SELECT 
    'Integridad Referencial' as categoria,
    'Facturas sin contrato válido' as regla,
    COUNT(*) as registros_problematicos,
    'CRÍTICO' as severidad,
    GROUP_CONCAT(b.id SEPARATOR '; ') as elementos_afectados
FROM BIA.bills b
LEFT JOIN BIA.contracts c ON b.contract_id = c.contract_id
WHERE c.contract_id IS NULL

UNION ALL

--  REGLA 2: Consistencia temporal y logica de negocio
SELECT 
    'Consistencia Temporal' as categoria,
    'Fechas inconsistentes en contratos' as regla,
    COUNT(*) as registros_problematicos,
    'ALTO' as severidad,
    GROUP_CONCAT(contract_id SEPARATOR '; ') as elementos_afectados
FROM BIA.contracts
WHERE end_date IS NOT NULL AND start_date IS NOT NULL AND end_date < start_date

UNION ALL

SELECT 
    'Consistencia Temporal' as categoria,
    'Pagos antes de fecha de corte' as regla,
    COUNT(*) as registros_problematicos,
    'MEDIO' as severidad,
    GROUP_CONCAT(p.id SEPARATOR '; ') as elementos_afectados
FROM BIA.payments p
INNER JOIN BIA.bills b ON p.bill_id = b.id
WHERE p.paid_at < b.cuttoff_date AND p.status = 'paid'

UNION ALL

--  REGLA 3: Valores de dominio y los rangos validos
SELECT 
    'Valores de Dominio' as categoria,
    'Consumos fuera de rango valido' as regla,
    COUNT(*) as registros_problematicos,
    'ALTO' as severidad,
    CONCAT('kWh negativos: ', 
           SUM(CASE WHEN kwh < 0 THEN 1 ELSE 0 END),
           ', kWh extremos (>15000): ',
           SUM(CASE WHEN kwh > 15000 THEN 1 ELSE 0 END)) as elementos_afectados
FROM BIA.consumptions
WHERE (kwh < 0 OR kwh > 15000) AND deleted_at IS NULL

UNION ALL

SELECT 
    'Valores de Dominio' as categoria,
    'Facturas con montos invalidos' as regla,
    COUNT(*) as registros_problematicos,
    'CRITICO' as severidad,
    CONCAT('Montos negativos o cero: ', COUNT(*)) as elementos_afectados
FROM BIA.bills
WHERE total <= 0

UNION ALL

--  REGLA 4: Completitud de datos criticos
SELECT 
    'Completitud de Datos' as categoria,
    'Campos obligatorios faltantes' as regla,
    (SELECT COUNT(*) FROM BIA.companies WHERE name IS NULL OR name = '') +
    (SELECT COUNT(*) FROM BIA.contracts WHERE company_id IS NULL) +
    (SELECT COUNT(*) FROM BIA.bills WHERE contract_id IS NULL OR period IS NULL) as registros_problematicos,
    'CRÍTICO' as severidad,
    'Empresas sin nombre, contratos sin company_id, facturas sin contrato/período' as elementos_afectados

UNION ALL

--  REGLA 5: Duplicados y unicos
SELECT 
    'Duplicados' as categoria,
    'Consumos duplicados por contrato-fecha-hora' as regla,
    COUNT(*) - COUNT(DISTINCT CONCAT(contract_id, DATE(date), hour, IFNULL(meter_id, 'NULL'))) as registros_problematicos,
    'ALTO' as severidad,
    'Registros duplicados en mediciones horarias' as elementos_afectados
FROM BIA.consumptions
WHERE deleted_at IS NULL

UNION ALL

SELECT 
    'Duplicados' as categoria,
    'Pagos multiples por factura' as regla,
    COUNT(*) - COUNT(DISTINCT bill_id) as registros_problematicos,
    'MEDIO' as severidad,
    'Facturas con multiples pagos exitosos' as elementos_afectados
FROM BIA.payments
WHERE status = 'paid';


