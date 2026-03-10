import logging
from fastapi import FastAPI
from .database import Base, engine
from .routes import router
from prometheus_client import Counter, generate_latest
from fastapi.responses import Response

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("skynet-service")

Base.metadata.create_all(bind=engine)

app = FastAPI(title="skynet-ops-audit-service")

REQUEST_COUNT = Counter("request_count", "Total API Requests")

@app.middleware("http")
async def count_requests(request, call_next):
    REQUEST_COUNT.inc()
    logger.info(f"Request received: {request.method} {request.url}")
    response = await call_next(request)
    return response

@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type="text/plain")

app.include_router(router)