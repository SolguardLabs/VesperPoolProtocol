# Security Policy

## Modelo de Seguridad

Vesper Pool Protocol asume que cada pool contiene dos activos con baja volatilidad relativa.
Los contratos están diseñados para tokens ERC-20 estándar sin fee-on-transfer, hooks ni rebases.

Roles principales:

- `owner`: administra parámetros, pausas y receptor de fees.
- `governor`: gestiona parámetros operativos en `VesperParameterStore`.
- `keeper`: registra snapshots en `VesperAccountingLedger`.
- `reporter`: publica observaciones en `VesperPegOracle`.

En despliegues de producción, estos roles deberían estar separados en multisigs o timelocks.

## Invariantes Esperadas

- Las reservas internas deben reconciliar con balances físicos tras `sync`.
- Las fees de protocolo se excluyen de reservas activas.
- Las LP shares representan una participación proporcional de reservas activas.
- Los swaps deben respetar `min_out`.
- Los retiros deben respetar límites de slippage indicados por el usuario.
- El pool no debe transferir fondos a direcciones cero.
- Las operaciones mutables principales están protegidas contra reentrada.

## Validación Automatizada

La validación local ejecuta:

```bash
python scripts/check_contracts.py
python -m ruff check tests scripts
python -m pytest -q
```

`scripts/check_contracts.py` compila todos los archivos Vyper en `src/`.

## Alcance de Revisión

Dentro de alcance:

- Contratos Vyper en `src/`.
- Tests Python en `tests/`.
- Scripts de compilación y CI.
- Accounting de reservas, LP shares, fees y retiros.

Fuera de alcance:

- Tokens con comportamiento no estándar.
- Oracles externos de producción.
- Integraciones cross-chain.
- Frontends o indexadores externos.

## Gestión de Dependencias

Dependabot revisa dependencias de Python y GitHub Actions semanalmente. Cualquier actualización
de Vyper o titanoboa debe acompañarse de compilación completa y ejecución de la suite.

## Reportes

Los reportes internos deben incluir:

- Resumen y severidad.
- Componente afectado.
- Impacto económico.
- Pasos de reproducción.
- Mitigación propuesta.
- Tests de regresión recomendados.

No incluir material sensible en issues públicos ni documentación de usuario.
