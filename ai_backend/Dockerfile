FROM python:3.12-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py ./

EXPOSE 8787

CMD ["sh", "-c", "gunicorn app:app -w 1 --threads 4 -b 0.0.0.0:${PORT:-8787} --timeout 75 --graceful-timeout 30 --keep-alive 5"]
