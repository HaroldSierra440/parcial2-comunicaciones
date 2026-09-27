\# Parcial 2 - Comunicaciones: Stack Multi-Contenedor



Infraestructura web con 5 servicios interconectados: Nginx (reverse proxy), Joomla (CMS), PostgreSQL (base de datos), Jupyter (analisis de datos) y Grafana (monitoreo), orquestados con Docker Compose.



\## Arquitectura



Navegador --HTTP:80--> nginx --+--> joomla (frontend\_net + backend\_net)

&#x20;                               +--> jupyter (frontend\_net + backend\_net)

&#x20;                               +--> grafana (frontend\_net + backend\_net)



joomla --TCP:5432--> database (solo backend\_net, aislada de internet)

grafana --TCP:5432--> database (lectura de metricas via rol grafana\_ro)

jupyter --TCP:5432--> database (lectura de metricas via rol joomla)



Ver el detalle completo en INFORME.md.



\## Requisitos previos



\- Docker Desktop instalado y en ejecucion (incluye Docker Compose v2).

\- En Windows: Docker Desktop instala WSL2 automaticamente si no lo tienes.



\## Como levantar el stack



git clone <URL\_DEL\_REPOSITORIO>

cd <CARPETA\_DEL\_REPOSITORIO>

cp .env.example .env

docker compose up -d



En Windows PowerShell, el "cp" equivale a:

Copy-Item .env.example .env



La primera vez tarda entre 3 y 6 minutos: descarga las imagenes base, construye la imagen de Jupyter y ejecuta la instalacion desatendida de Joomla.



\## Verificar que todo quedo arriba



docker compose ps



Los 5 contenedores deben aparecer como Up y (healthy).



\## Acceso a los servicios



Portal Joomla:    http://localhost/

Backend Joomla:   http://localhost/administrator/   (administrador / Comm2026\_Joomla\_Admin)

JupyterLab:       http://localhost/jupyter/          (sin token, cuaderno precargado: analisis\_datos.ipynb)

Grafana:          http://localhost/grafana/          (admin / Comm2026\_Grafana, lectura anonima habilitada)



\## Generar trafico de demostracion



Linux/macOS:

scripts/generar\_trafico.sh 15



Windows PowerShell:

powershell -ExecutionPolicy Bypass -File scripts\\generar\_trafico.ps1 -Vueltas 15



\## Estructura del repositorio



stack-comunicaciones/

|-- docker-compose.yml

|-- .env.example

|-- .env

|-- README.md

|-- INFORME.md

|-- nginx/conf.d/default.conf

|-- joomla/apache/zz-observabilidad.conf

|-- database/initdb/01-observabilidad.sql

|-- database/initdb/02-rol-grafana.sh

|-- jupyter/Dockerfile

|-- jupyter/config/jupyter\_server\_config.py

|-- jupyter/notebooks/analisis\_datos.ipynb

|-- grafana/provisioning/datasources/datasource.yml

|-- grafana/provisioning/dashboards/dashboard.yml

|-- grafana/provisioning/dashboards/json/observabilidad\_joomla.json

`-- scripts/generar\_trafico.sh, generar\_trafico.ps1



\## Autor



Universidad Militar Nueva Granada - Ingenieria Mecatronica - Comunicaciones

Parcial 2 practico

