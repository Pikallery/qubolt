from __future__ import annotations

from fastapi import HTTPException, status


class QLoopException(HTTPException):
    pass


class NotFoundError(QLoopException):
    def __init__(self, resource: str, id: str | None = None):
        detail = f"{resource} not found" + (f": {id}" if id else "")
        super().__init__(status_code=status.HTTP_404_NOT_FOUND, detail=detail)


class ForbiddenError(QLoopException):
    def __init__(self, detail: str = "Insufficient permissions"):
        super().__init__(status_code=status.HTTP_403_FORBIDDEN, detail=detail)


class TenantNotFoundError(QLoopException):
    def __init__(self, slug: str | None = None):
        detail = f"Tenant not found" + (f": {slug}" if slug else "")
        super().__init__(status_code=status.HTTP_404_NOT_FOUND, detail=detail)


class PlanLimitError(QLoopException):
    def __init__(self, resource: str, limit: int):
        super().__init__(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail=f"Plan limit reached for {resource} (max {limit}). Upgrade your plan.",
        )


class IngestionError(QLoopException):
    def __init__(self, detail: str):
        super().__init__(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=detail)
