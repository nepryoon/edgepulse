FROM python:3.11-slim

WORKDIR /app

# System deps (optional; keep minimal)
RUN pip install --no-cache-dir --upgrade pip

COPY pyproject.toml /app/pyproject.toml
COPY edgepulse_ml /app/edgepulse_ml

RUN pip install --no-cache-dir .

ENV MODEL_DIR=/tmp/models

ENTRYPOINT ["edgepulse-ml"]
