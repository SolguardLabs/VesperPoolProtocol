# Arquitectura y flujos

`VesperPool` mantiene dos reservas, fees segregadas, suministro LP, amplificación e invariante. `VesperRouter` agrupa llamadas con deadline y pools confiables. `VesperPoolLens` ofrece cotizaciones y posiciones; `VesperPoolMonitor` agrega salud de peg, concentración y liquidez; `VesperScenarioLens` aplica shocks de precio y retiros hipotéticos sin escribir estado. `VesperPegOracle` publica precios y frescura. `VesperAccountingLedger` registra checkpoints operativos por época.

```mermaid
sequenceDiagram
    participant LP as Proveedor
    participant R as Router
    participant P as Pool
    participant O as Oracle
    participant L as Lentes
    participant C as Ledger
    LP->>R: Aportación o retiro con límites
    R->>P: Operación admitida
    P-->>LP: Tokens o shares LP
    O-->>L: Precio y heartbeat
    P-->>L: Reservas, fees e invariante
    P-->>C: Estado consultado por keeper
```

Los roles de propietario, gobernador, keeper y reporter tienen alcance distinto. El monitor y las lentes son superficies de lectura; sus indicadores pueden apoyar decisiones operativas, pero no cambian las reglas del pool. El mock ERC-20 se utiliza en fixtures locales.

| Componente | Escribe | Consulta |
| --- | --- | --- |
| Pool | reservas, fees, LP | oráculo solo mediante módulos externos |
| Router | lista de pools | pool |
| Oráculo | precios y rondas | parámetros de heartbeat |
| Ledger | snapshots | pool |
| Lentes | nada | pool y oráculo |
