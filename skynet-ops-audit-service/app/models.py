from sqlalchemy import Column, String, DateTime
from sqlalchemy.sql import func
from .database import Base
import uuid

class Event(Base):
    __tablename__ = "events"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    type = Column(String)
    tenantId = Column(String)
    severity = Column(String)
    message = Column(String)
    source = Column(String)
    created_at = Column(DateTime(timezone=True), server_default=func.now())