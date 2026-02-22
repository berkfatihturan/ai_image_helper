from fastapi import APIRouter
from src.api.routes import ui

api_router = APIRouter()
api_router.include_router(ui.router, prefix="/ui", tags=["UI Automation"])
