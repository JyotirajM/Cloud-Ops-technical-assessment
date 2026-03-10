from pydantic import BaseModel
from enum import Enum

class Severity(str, Enum):
    info = "info"
    warning = "warning"
    error = "error"
    critical = "critical"

class EventCreate(BaseModel):
    type: str
    tenantId: str
    severity: Severity
    message: str
    source: str