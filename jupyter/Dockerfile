FROM jupyter/base-notebook:latest

USER root

COPY config/jupyter_server_config.py /home/jovyan/.jupyter/jupyter_server_config.py
RUN chown -R "${NB_UID}:${NB_GID}" /home/jovyan/.jupyter

USER ${NB_UID}

RUN pip install --no-cache-dir --quiet \
        "psycopg2-binary==2.9.10" \
        "SQLAlchemy==2.0.36" \
        "pandas==2.2.3" \
        "matplotlib==3.9.2" \
        "requests==2.32.3" \
        "tabulate==0.9.0" && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

WORKDIR /home/jovyan
EXPOSE 8888