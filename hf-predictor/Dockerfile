FROM python:3.11-slim

# Instalar dependencias necesarias del sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgfortran5 \
    redis-tools \
 && rm -rf /var/lib/apt/lists/*

# Copiar binario funcional ITURHFProp y librerías compartidas
COPY data/iturhf/bin/ITURHFProp /usr/bin/ITURHFProp
COPY data/iturhf/lib/libp372.so /usr/lib/libp372.so
COPY data/iturhf/lib/libp533.so /usr/lib/libp533.so

# Copiar archivos de datos de ITURHFProp
COPY data/iturhf/data/ /opt/iturhf/data/

# Copiar plantilla a ruta esperada por ITURHFProp (por si hiciera falta)
RUN mkdir -p /usr/share/iturhfprop/data/ && \
    cp /opt/iturhf/data/ITU-R-HF.in /usr/share/iturhfprop/data/

# Establecer directorio de trabajo
WORKDIR /app

# Instalar dependencias de Python
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar el resto de la aplicación
COPY app/ /app/

# Ejecutar la aplicación FastAPI
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
