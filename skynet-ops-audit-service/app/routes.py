from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from .database import SessionLocal
from . import models, schemas
from datetime import datetime
import os

router = APIRouter()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@router.get("/health")
def health():
    return {
        "status": "ok",
        "service": os.getenv("SERVICE_NAME", "skynet-ops-audit-service"),
        "environment": os.getenv("APP_ENV", "dev"),
        "timestamp": datetime.utcnow()
    }


@router.post("/events", status_code=201)
def create_event(event: schemas.EventCreate, db: Session = Depends(get_db)):

    severity = event.severity.lower()

    if severity not in ["info", "warning", "error", "critical"]:
        raise HTTPException(status_code=400, detail="Invalid severity")

    event_data = event.dict()
    event_data["severity"] = severity

    db_event = models.Event(**event_data)
    db.add(db_event)
    db.commit()
    db.refresh(db_event)

    return {
        "success": True,
        "eventId": db_event.id,
        "storedAt": db_event.created_at
    }


@router.get("/events")
def get_events(
        tenantId: str = None,
        severity: str = None,
        limit: int = 20,
        offset: int = 0,
        db: Session = Depends(get_db)
):

    if limit > 100:
        limit = 100

    query = db.query(models.Event)

    if tenantId:
        query = query.filter(models.Event.tenantId == tenantId)

    if severity:
        query = query.filter(models.Event.severity == severity)

    total = query.count()

    events = (
        query.order_by(models.Event.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )

    return {
        "items": events,
        "total": total,
        "limit": limit,
        "offset": offset
    }

import time
import logging
from fastapi import Query

logger = logging.getLogger(__name__)


@router.get("/metrics-demo")
def metrics_demo(mode: str = Query("normal")):

    if mode == "error":
        raise HTTPException(status_code=500, detail="Simulated error")

    if mode == "slow":
        time.sleep(2)
        return {"status": "slow response"}

    if mode == "burst":
        for i in range(10):
            logger.info(f"Burst log event {i}")
        return {"status": "burst logs generated"}

    return {"status": "ok"}