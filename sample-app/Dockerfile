# ---------------------------------------------------------------------------
# Sample application Dockerfile
#
# Build:
#   docker build -t my-app:latest sample-app/
#
# For the Virtuozzo cluster, tag and push to your registry, then update
# apps/my-app/deployment.yaml with the new image.
# ---------------------------------------------------------------------------

FROM python:3.12-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim

WORKDIR /app
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY app.py .

EXPOSE 8080

USER 1000:1000

CMD ["python", "app.py"]
