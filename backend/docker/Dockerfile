FROM python:3.11-slim

# Dependências de sistema para librosa/ffmpeg
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libsndfile1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copia código e catálogos
COPY backend/app/ ./app/
COPY catalogs/ ./catalogs/

ENV PYTHONUNBUFFERED=1
ENV CATALOGS_DIR=/app/catalogs

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
