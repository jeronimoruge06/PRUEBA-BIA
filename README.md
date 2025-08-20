-- =====================================================
--  PRUEBA TECNICA BIA
-- =====================================================

1. ÍNDICES  
   - Los índices sugeridos se pueden crear directamente en la base de datos usando los comandos indicados en este README.
   - Ejemplos de índices ya implementados se encuentran en [BIA.sql](BIA.sql), en las secciones de cada tabla (ver líneas con `CREATE INDEX`).

2. PARTICIONAMIENTO  
   - El particionamiento no está implementado en los scripts actuales, pero se recomienda crear tablas por periodo (ejemplo: bills_2024_07).
   - Para implementar, se deben modificar los scripts de creación en [BIA.sql](BIA.sql) y adaptar las consultas en [query.sql](query.sql) y [KPI.sql](KPI.sql).

3. MATERIALIZACIÓN  
   - La idea de materializar KPIs se puede implementar creando una tabla resumen como `kpi_resumen`.
   - Ejemplo de cómo calcular KPIs está en [KPI.sql](KPI.sql), donde se pueden adaptar las consultas para guardar resultados en una tabla adicional.

4. Consultas de KPI y optimización  
   - Las consultas que requieren optimización están en [KPI.sql](KPI.sql) y [query.sql](query.sql).
   - Los índices recomendados para mejorar el rendimiento de estas consultas están listados al final de [query.sql](query.sql).

5. Reglas de calidad de datos  
   - Las reglas de control y chequeos de calidad se encuentran en la sección "DATA QUALITY CHECKS" de [query.sql](query.sql).

-- =====================================================
-- 3.  PERFORMANCE 
-- =====================================================

PROBLEMA:
Las query del KPI están lentas cuando hay muchos datos, tardan demas en ejecutarse.

SOLUCIONES PROPUESTAS:

1. INDICES (LO MAS FACIL DE IMPLEMENTAR)

Que son: Como un indice de un libro, ayudan a encontrar datos mucho mas rapido.

Cuales podriamos crear:
- En bills: CREATE INDEX idx_bills_period_status ON bills(period, status);
- En payments: CREATE INDEX idx_payments_bill_paid ON payments(bill_id, paid_at);
- En consumptions: CREATE INDEX idx_consumptions_contract_date ON consumptions(contract_id, date);

Porque funciona: En vez de revisar toda la tabla  MySQL va directo a los datos que necesitan.

Ejemplo:
Sin indice: Buscar todas las facturas de julio = revisar 1 millon de registros
Con indice: Buscar todas las facturas de julio = revisar 5,000 registros

2. PARTICIONAMIENTO 

Que es: Dividir una tabla grande en tablas mas pequeñas por fecha.

Como se ve:
- Tabla bills_2024_01 
- Tabla bills_2024_02  
- Tabla bills_2024_07 

Beneficio: Cuando pregunto por julio 2024, solo busca en esa "cajita", mas no en toda la bodega.

3. MATERIALIZACION 

Que es: Pre-calcular y guardar los resultados que usamos mucho.

Ejemplo:
En vez de calcular "suma de las facturas de julio" cada vez que alguien pregunta,
mejor calcularlo una vez al dia y lo guardamos en una tabla.

Tabla ejemplo:
kpi_resumen:
- period: 2024-07
- total_facturado: 278600
- total_facturas: 45
- calculado_el: 2024-07-31

CUAL HACER PRIMERO:

1. INDICES 
  - Tiempo: 30 minutos
  - Riesgo: Muy bajo
  - Beneficio: 70% más rapido

2. PARTICIONAMIENTO 
  - Tiempo: 1 semana
  - Riesgo: Medio (ya quw hay que migrar datos)
  - Beneficio: 90% más rapido en queries por mes

3. MATERIALIZACIÓN 
  - Tiempo: 2 semanas  
  - Riesgo: Alto 
  - Beneficio: Resultados instantaneos

INDICES PARA EMPEZAR:
CREATE INDEX idx_bills_period ON bills(period);
CREATE INDEX idx_payments_paid_at ON payments(paid_at);
CREATE INDEX idx_consumptions_contract ON consumptions(contract_id);
