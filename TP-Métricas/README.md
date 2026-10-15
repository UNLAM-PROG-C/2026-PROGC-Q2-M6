# Airline concurrency simulator

Aplicación de consola multihilo que simula asignación dinámica de aviones a vuelos. Está escrita para Python 3.11+, usa la biblioteca estándar y `psutil`, y contiene un dashboard HTML servido por `http.server`.

La ejecución registra métricas del proceso con `psutil`: CPU promedio y máxima,
tiempo de CPU, memoria RSS inicial/máxima/final y cantidad de hilos. El monitor
existente toma las muestras sin bloquear las secciones críticas y genera un
resumen en consola junto con `metrics.json`.

## Ejecución local

```bash
python3 -m pip install -r requirements.txt
python3 main.py --duration 20 --planes 8 --flights 40 --assigners 3 --speed 10 --seed 42
```

Abra [http://127.0.0.1:8080](http://127.0.0.1:8080) mientras corre la simulación. `--no-dashboard` desactiva el servidor. La duración está en segundos reales y `--speed 10` significa diez minutos simulados por segundo real.

El archivo de métricas se puede cambiar con `--metrics-file`, por ejemplo:

```bash
python3 main.py --duration 20 --no-dashboard --metrics-file metrics-core.json
```

Todos los parámetros configurables son `--duration`, `--planes`, `--flights`, `--assigners`, `--speed`, `--seed`, `--port` y `--metrics-file`. La semilla se propaga a cada generador de aleatoriedad para que una ejecución sea reproducible bajo las mismas condiciones.

## Docker

Para ejecutar el proyecto con Docker necesitás tener Docker instalado y el
puerto `8080` disponible en tu equipo.

Primero construí la imagen desde la raíz del repositorio:

```bash
docker build -t airline-simulator .
```

Luego ejecutá una simulación con el dashboard habilitado:

```bash
docker run --rm -p 8080:8080 airline-simulator \
  --duration 30 \
  --planes 8 \
  --flights 40 \
  --assigners 3 \
  --speed 10 \
  --seed 42
```

Mientras el contenedor esté activo, abrí
[http://localhost:8080](http://localhost:8080) para consultar el dashboard.
También podés consultar el estado en formato JSON desde otra terminal:

```bash
curl http://localhost:8080/api/state
```

El servidor escucha en `0.0.0.0` dentro del contenedor y `-p 8080:8080`
publica ese puerto en el host. Mantené el contenedor ejecutándose durante la
consulta; la simulación se apaga automáticamente al finalizar `--duration`.

Para conservar el reporte de métricas en el host, montá una carpeta local como
volumen y escribí el reporte dentro de ella:

```bash
mkdir -p salidas

docker run --rm -p 8080:8080 \
  -v "$(pwd)/salidas:/app/salidas" \
  airline-simulator \
  --duration 20 \
  --no-dashboard \
  --metrics-file /app/salidas/metrics.json
```

Al finalizar, el reporte estará disponible en `salidas/metrics.json`.

Si no necesitás el dashboard, podés ejecutar el contenedor sin publicar ningún
puerto:

```bash
docker run --rm airline-simulator \
  --duration 5 \
  --no-dashboard \
  --metrics-file /app/metrics-docker.json
```

`--duration` se expresa en segundos reales. `--speed 10` significa que la
simulación avanza diez minutos simulados por cada segundo real. El contenedor
finaliza automáticamente cuando termina la duración configurada.

## Diseño de concurrencia

`SharedState.condition` protege los diccionarios de vuelos y aviones, la selección y la mutación de una asignación. Los asignadores entran a la misma región crítica: elegir vuelo, elegir avión compatible y cambiar ambos estados es una sola operación atómica. Así no existe un check-then-act separado.

Cada avión tiene un `threading.RLock`. Cuando se deben adquirir varios locks, `acquire_plane_locks` los ordena por `plane_id` y los libera en orden inverso. Todas las rutas que necesitan más de un avión respetan esa regla; esto evita ciclos de espera y deadlocks. El snapshot del monitor toma el lock global y luego los locks de aviones ordenados, por lo que lee una imagen consistente.

Los asignadores esperan en `Condition.wait` cuando no pueden avanzar y los hilos de avión esperan la misma condición cuando no tienen trabajo. No se usa `time.sleep` para sincronizar: los tiempos de simulación usan `Event.wait` y los cambios de estado usan `Condition.notify_all`. Al cerrar, el `Event` global despierta a los hilos y se agregan sentinelas `None` a la cola de vuelos.

La prioridad efectiva es `peso + minutos_de_espera / aging_minutes`. El aging crece sin límite, por lo que un vuelo regular o de carga eventualmente supera prioridades nuevas. Se selecciona el vuelo más prioritario entre los que tienen al menos un avión compatible; luego se minimiza el tiempo ocioso y el exceso de capacidad del avión.

Al asignar, el horario se ajusta como mínimo a `available_since` del avión cuando el vuelo ya quedó retrasado. Esto evita solapamientos con vuelos históricos del mismo avión y queda registrado como demora.

## Estados e invariantes

Las tablas `PLANE_TRANSITIONS` y `FLIGHT_TRANSITIONS` en `models.py` son la única fuente de transiciones válidas. `transition` lanza `InvalidTransition` ante cualquier salto no permitido. El monitor verifica periódicamente con aserciones: conteo total de estados, unicidad de asignaciones, ningún avión en mantenimiento asignado, y espera acotada cuando existe un avión compatible. Los errores se registran con nivel `ERROR`.

Una falla de mantenimiento sobre un avión asignado devuelve el vuelo a pendiente y libera el avión para mantenimiento. Una demora cambia el horario simulado, queda registrada y, si el vuelo ya está asignado, naturalmente retrasa la disponibilidad del avión para el siguiente vuelo.

## Tests de estrés

```bash
python3 -m unittest discover -s tests -v
```

El caso principal utiliza 50 aviones, 500 vuelos y 8 asignadores simultáneos.
También se repite con varias semillas. Al finalizar detiene los hilos, notifica
la condición, comprueba que ningún worker quede vivo y valida nuevamente todos
los invariantes.

El reporte `metrics.json` deja evidencia de funcionalidades (vuelos generados,
completados, cancelados, demoras y mantenimiento) y de concurrencia
(invariantes, hilos restantes y exclusión mutua). La evidencia se interpreta
con la rúbrica de sincronización, deadlocks, condiciones de carrera y
exclusión mutua.

## Riesgos evitados

* Sin el `Condition`, un asignador podría consultar continuamente y consumir CPU; también podría no observar una liberación de avión a tiempo.
* Sin el orden global de locks, dos operaciones que necesitaran dos aviones podrían adquirirlos en orden inverso y quedar bloqueadas para siempre.
* Sin la región crítica única, dos asignadores podrían observar el mismo avión disponible y asignarlo a vuelos diferentes.
* Sin el snapshot consistente, el monitor podría leer un vuelo asignado mientras el avión todavía parece disponible y reportar falsos errores.
* Sin aging, una corriente continua de emergencias/VIP podría postergar indefinidamente vuelos regulares o de carga.
* Sin `Event` y sentinelas, un hilo bloqueado en una cola o condición podría sobrevivir al final de la simulación.
