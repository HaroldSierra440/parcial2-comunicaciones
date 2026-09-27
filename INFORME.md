# INFORME TECNICO - Parcial 2: Stack Multi-Contenedor

Universidad Militar Nueva Granada - Ingenieria Mecatronica - Comunicaciones

## Seccion 1: Topologia y Flujo de Informacion

### Diagrama de arquitectura

```
Navegador del Usuario / Cliente
        |
        | HTTP (Puerto 80:80) -- unico puerto publicado al host
        v
   +---------+
   |  nginx  |  (Reverse Proxy, frontend_net: 172.28.10.5)
   +---------+
     |    |    |
     |    |    +-- HTTP interno --> grafana (172.28.10.4 / 172.28.20.3)
     |    +------- HTTP / WebSockets --> jupyter (172.28.10.2 / 172.28.20.4)
     +------------ HTTP interno --> joomla (172.28.10.3 / 172.28.20.5)
                                         |
                                         | TCP:5432
                                         v
                                    +----------+
                                    | database |  (PostgreSQL, SOLO backend_net: 172.28.20.2)
                                    +----------+
                                         ^
                        Lectura de metricas / logs (rol grafana_ro, rol joomla)
                                         |
                          grafana -------+------- jupyter
```

Redes:
- frontend_net (172.28.10.0/24): nginx, joomla, jupyter, grafana
- backend_net (172.28.20.0/24, internal=true): joomla, database, jupyter, grafana

El contenedor `database` esta unicamente en `backend_net`, que ademas se declaro con
`internal: true` en el docker-compose.yml. Esto significa que ni siquiera tiene una
ruta de salida hacia internet o hacia el host: solo es alcanzable por los contenedores
que comparten esa red interna.

### Mecanismo de recoleccion de logs y metricas

El stack NO usa un agente externo de logging (tipo Promtail, Fluentd o Filebeat).
En su lugar, PostgreSQL mismo lee los archivos de log directamente del disco:

1. Nginx escribe cada peticion en formato JSON a `/var/log/nginx/shared/access.json.log`
   (definido en `nginx/conf.d/default.conf`, log_format `edge_json`). Ese archivo vive
   en el volumen nombrado `edge_logs`.
2. Apache (dentro del contenedor Joomla) escribe en paralelo un log JSON propio en
   `/var/log/apache2/joomla_access.json.log` (definido en `joomla/apache/zz-observabilidad.conf`,
   LogFormat `joomla_json`). Ese archivo vive en el volumen `joomla_logs`.
3. El contenedor `database` monta AMBOS volumenes de logs, en modo solo lectura:
   `edge_logs:/mnt/logs/edge:ro` y `joomla_logs:/mnt/logs/joomla:ro`.
4. Dentro de PostgreSQL, funciones `SECURITY DEFINER` (`observabilidad.leer_lineas` y
   `observabilidad.leer_json`, creadas en `database/initdb/01-observabilidad.sql`) usan
   `pg_read_file()` para leer el archivo de log desde el disco, tomar solo la cola
   reciente (acotado a 8 MB) y convertir cada linea a JSONB.
5. Vistas SQL (`observabilidad.nginx_access`, `observabilidad.joomla_access`,
   `observabilidad.trafico`) parsean ese JSONB a columnas tipadas (timestamp, ip,
   metodo, uri, status, duracion, etc.).
6. Grafana y Jupyter consultan esas vistas como si fueran tablas SQL normales, via
   un rol de solo lectura (`grafana_ro`, creado en `database/initdb/02-rol-grafana.sh`)
   con permisos minimos (SELECT sobre el esquema `observabilidad`, EXECUTE sobre las
   funciones de lectura, y el rol `pg_monitor` para metricas internas del motor).

Ventaja de este enfoque: un solo motor (PostgreSQL) sirve como fuente unica de verdad
tanto para los datos de Joomla como para las metricas de observabilidad, sin anadir
un sexto contenedor al stack.

## Seccion 2: Analisis Detallado del Modelo OSI en la Solucion

### Capa 7 (Aplicacion)

**Cabeceras HTTP inyectadas por Nginx:**
- `Host`: se reenvia el host original pedido por el navegador (`$http_host`), para que
  Joomla y Grafana generen enlaces internos correctos en vez de usar el nombre interno
  del contenedor.
- `X-Forwarded-For`: contiene la IP real del cliente. Apache (dentro de Joomla) confia
  en esta cabecera solo si la peticion llega desde las subredes internas del stack
  (`RemoteIPInternalProxy 172.28.10.0/24` y `172.28.20.0/24`, configurado en
  `joomla/apache/zz-observabilidad.conf`), evitando que un cliente externo falsifique
  su propia IP.
- `X-Forwarded-Proto`: indica el esquema original (http/https) para que las aplicaciones
  backend generen URLs con el protocolo correcto.

**Mecanismo de HTTP Upgrade para WebSockets (Jupyter):**
El kernel de Jupyter usa WebSockets para mantener la conexion interactiva entre el
navegador y el kernel de Python. Un WebSocket comienza como una peticion HTTP normal
que pide "actualizarse" a otro protocolo mediante las cabeceras:

```
Upgrade: websocket
Connection: Upgrade
```

En `nginx/conf.d/default.conf` esto se resuelve con:

```
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
```

y dentro del location `/jupyter/`:

```
proxy_set_header Upgrade    $http_upgrade;
proxy_set_header Connection $connection_upgrade;
proxy_buffering off;
proxy_read_timeout 86400s;
```

Sin estas lineas, Nginx cerraria la conexion tratandola como HTTP normal, y JupyterLab
mostraria "Kernel connection error". Un detalle relevante de Nginx: cuando un bloque
`location` define CUALQUIER `proxy_set_header`, deja de heredar los del bloque `server`
padre — por eso el location de `/jupyter/` (y el de `/grafana/`) repiten TODAS las
cabeceras (Host, X-Real-IP, X-Forwarded-*) ademas de anadir Upgrade/Connection.

**Protocolo de aplicacion de PostgreSQL:**
PostgreSQL usa su propio protocolo binario de Capa 7 sobre TCP (no HTTP). El flujo
tipico es: handshake inicial -> autenticacion (usuario/password) -> ciclo de mensajes
Query/Parse/Bind/Execute -> respuesta con filas en formato binario o texto. Tanto
`psycopg2` (usado en el notebook de Jupyter) como el datasource nativo de Grafana
para PostgreSQL implementan este protocolo directamente, sin pasar por HTTP.

**Formato de logs de Joomla:**
El LogFormat `joomla_json` (definido en `joomla/apache/zz-observabilidad.conf`) genera
una linea JSON por peticion con: timestamp ISO 8601, IP del cliente, IP del proxy,
X-Forwarded-For, host, metodo HTTP, URI, protocolo, codigo de status, bytes
transferidos, duracion en microsegundos, referer y user-agent.

### Capa 4 (Transporte)

**Puertos TCP involucrados:**
- 80: Nginx (unico puerto publicado al host, `80:80`).
- 5432: PostgreSQL, expuesto SOLO dentro de `backend_net` (sin `ports:` en el
  docker-compose.yml, por lo que no es alcanzable desde el host ni desde internet).
- 8888: Jupyter (interno, tras el proxy).
- 3000: Grafana (interno, tras el proxy).

**Conexiones concurrentes y persistentes:**
- Nginx usa `proxy_http_version 1.1`, lo que habilita conexiones keep-alive hacia los
  backends (Joomla, Jupyter, Grafana), reutilizando la misma conexion TCP para varias
  peticiones en vez de abrir/cerrar una por cada una.
- La conexion de Joomla hacia PostgreSQL se mantiene abierta durante la vida del proceso
  de Apache que la origino (pool implicito manejado por el driver PHP de PostgreSQL).
- El notebook de Jupyter abre una conexion TCP persistente via `psycopg2.connect()`,
  que se reutiliza para las multiples consultas de las celdas 4, 5 y 6 sin reconectar.
- Grafana mantiene un pool de conexiones hacia PostgreSQL configurado explicitamente en
  el datasource (`maxOpenConns: 5`, `maxIdleConns: 2`, `connMaxLifetime: 14400` segundos),
  para no saturar la base de datos con conexiones nuevas en cada refresco del dashboard
  (cada 30 segundos).

### Capa 3 (Red)

**Direccionamiento IP y aislamiento:**
- `frontend_net`: subred `172.28.10.0/24`, gateway `172.28.10.1`. Conecta a nginx
  (.5), joomla (.3), jupyter (.2) y grafana (.4).
- `backend_net`: subred `172.28.20.0/24`, gateway `172.28.20.1`, declarada `internal: true`.
  Conecta a database (.2), joomla (.5), jupyter (.4) y grafana (.3).
- Al ser `internal: true`, Docker NO crea una regla de NAT/masquerade para esa red hacia
  la interfaz externa del host: los contenedores de `backend_net` no tienen salida a
  internet, y nada externo puede iniciar una conexion hacia ellos. `database` queda asi
  completamente aislado del exterior, solo alcanzable por los contenedores que comparten
  esa red interna.

**DNS embebido de Docker:**
Docker corre un servidor DNS interno en `127.0.0.11` dentro de cada contenedor. Cuando
el codigo de una aplicacion resuelve un nombre como `database` o `joomla`, esa consulta
llega a `127.0.0.11`, que responde con la IP fija asignada a ese servicio en la red que
comparten. Esto se demostro en la Celda 2 del notebook (`socket.gethostbyname`), donde
`nginx`, `joomla`, `database` y `grafana` resolvieron a sus IPs fijas exactas definidas
en el `docker-compose.yml`. Nginx mismo declara `resolver 127.0.0.11 valid=10s;` en su
configuracion para resolver los nombres de los backends dinamicamente.

**NAT y reenvio administrados por el kernel del host:**
El puerto publicado `80:80` de Nginx se traduce mediante reglas `iptables` (o `nftables`,
segun el motor de Docker) que el propio Docker Engine instala en el kernel del host: el
trafico que llega al puerto 80 del host se reenvia (DNAT) hacia la IP interna de Nginx
dentro de `frontend_net`. De igual forma, cuando un contenedor de `frontend_net` (no
`internal`) necesita salir a internet (por ejemplo, para descargar una imagen), el kernel
aplica SNAT/masquerade para que el trafico saliente use la IP del host.

### Capa 2 (Enlace de Datos)

**Interfaces virtuales y puentes:**
Cada red bridge definida en el `docker-compose.yml` (`frontend_net`, `backend_net`) se
materializa como un bridge Linux (`br-xxxxx`) en el host. Por cada contenedor conectado
a una red, Docker crea un par de interfaces virtuales Ethernet (`veth`): un extremo vive
dentro del namespace de red del contenedor (aparece como `eth0`), y el otro extremo se
conecta al bridge correspondiente en el host. Un contenedor conectado a dos redes (como
`joomla`, que esta en `frontend_net` y `backend_net`) tiene dos pares `veth`, uno por
cada bridge, y por tanto dos interfaces (`eth0`, `eth1`) dentro de su namespace.

**Resolucion ARP interna:**
Cuando dos contenedores en el mismo bridge (por ejemplo `joomla` y `database`, ambos en
`backend_net`) necesitan comunicarse, antes de enviar el primer paquete IP el kernel
del contenedor origen resuelve la direccion MAC del destino mediante una consulta ARP
("who has 172.28.20.2?") que se propaga por el bridge Linux hacia todos los `veth`
conectados a el. El contenedor `database` responde con su direccion MAC, y a partir de
ahi la comunicacion Capa 2 queda establecida y cacheada en la tabla ARP del origen. Este
mecanismo es identico al de una red fisica LAN, solo que aqui el "cable" es el bridge
virtual del host.

## Seccion 3: Guia de Verificacion y Demostracion

### 1. Abrir el portal Joomla y generar trafico

1. Levantar el stack: `docker compose up -d` y esperar a que los 5 contenedores
   muestren `(healthy)` en `docker compose ps`.
2. Abrir `http://localhost/` en el navegador: debe cargar el portal Joomla con el
   tema Cassiopeia.
3. Navegar por el sitio (Home, unos clics) y opcionalmente entrar al backend en
   `http://localhost/administrator/` con `administrador` / `Comm2026_Joomla_Admin`.
4. Generar trafico de demostracion adicional con el script incluido:
   - Windows: `powershell -ExecutionPolicy Bypass -File scripts\generar_trafico.ps1 -Vueltas 15`
   - Linux/macOS: `scripts/generar_trafico.sh 15`

   Esto lanza peticiones repetidas contra varias rutas (home, admin, rutas
   inexistentes, health checks de cada servicio) a traves de Nginx.

### 2. Abrir Grafana y verificar las graficas

1. Abrir `http://localhost/grafana/`. La lectura anonima esta habilitada, por lo que
   el dashboard es visible sin loguearse; para editar, usar `admin` / `Comm2026_Grafana`.
2. Ir a Dashboards > Parcial 2 - Comunicaciones > Parcial 2 - Observabilidad.
3. Confirmar que los paneles muestran datos (no aparecen vacios): tabla de rutas mas
   visitadas, trafico por servicio en el tiempo, IPs con mas actividad, codigos de
   respuesta HTTP, latencia del edge (p50/p95) y tablas de Joomla en PostgreSQL.
4. Estos paneles se cargan automaticamente al arrancar el contenedor, leyendo el
   archivo `grafana/provisioning/dashboards/json/observabilidad_joomla.json` — no se
   requiere ninguna configuracion manual en la interfaz.

### 3. Ejecutar el cuaderno de Jupyter

1. Abrir `http://localhost/jupyter/`. No pide token ni contrasena.
2. El cuaderno `analisis_datos.ipynb` (dentro de la carpeta `work/`) ya esta precargado.
3. Ejecutar todas las celdas con Run > Run All Cells:
   - Celda 1: confirma que las librerias (psycopg2, pandas, matplotlib, requests) estan
     instaladas.
   - Celda 2: resuelve por DNS los nombres de los servicios (`nginx`, `joomla`,
     `database`, `grafana`), confirmando el DNS interno de Docker.
   - Celda 3: genera trafico HTTP contra Nginx desde dentro de la red interna.
   - Celda 4: se conecta a PostgreSQL usando las variables de entorno inyectadas por
     Docker Compose.
   - Celda 5: consulta la vista `observabilidad.trafico` y grafica peticiones por
     servicio y por clase de codigo HTTP.
   - Celda 6: consulta la vista `observabilidad.actividad_bd` con metricas internas
     del motor PostgreSQL (conexiones activas, cache hit ratio, transacciones).
4. Todas las celdas deben ejecutarse sin errores, confirmando la cadena completa:
   Nginx escribe logs -> PostgreSQL los lee del disco -> las vistas SQL los exponen ->
   Jupyter y Grafana los consumen.


