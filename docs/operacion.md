# Operación y validación

## Entorno reproducible

Use Python 3.12 y las versiones exactas de `requirements.txt`. La suite no requiere RPC externo. `scripts/check_contracts.py` compila todos los `.vy` de `src/`; Ruff analiza scripts y pruebas; pytest despliega contratos con titanoboa.

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python scripts/check_contracts.py
python -m ruff check tests scripts
python -m pytest -q
```

En PowerShell, use `.\.venv\Scripts\python.exe` en lugar de activar el entorno si la política de ejecución lo impide. El script Bash `scripts/ci.sh` crea una venv cuando falta y ejecuta la misma secuencia.

## Diagnóstico de pool

1. Lea `activeReserves()` y `protocolFees()` junto a balances físicos.
2. Compare `invariant()` y `lastInvariant()` tras una operación.
3. Consulte estado de peg y heartbeat antes de un escenario de estrés.
4. Registre un snapshot con el ledger para comparar épocas.
5. Para una discrepancia, conserve commit, parámetros, secuencia de transacciones y salidas completas.

Un `valueLossBps` de la lente expresa sensibilidad al shock suministrado, no una pérdida realizada. Si el precio está caducado o no hay ronda, la lente revierte. Las cotizaciones son válidas solo para el estado en que se leen; el caller debe volver a comprobar los límites al ejecutar.

## Entrega versionada

Antes de publicar, contraste el SHA de `main`, `production` y el tag anotado
`v2.0.0`; ejecute compilación, Ruff y pytest sobre el commit exacto. El
verificador de integridad de GitHub confirma refs y versión declarada en
`pyproject.toml`. El release debe quedar publicado, no draft ni prerelease.
