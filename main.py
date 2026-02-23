import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.core.config import settings
from src.api.router import api_router

def get_application() -> FastAPI:
    application = FastAPI(
        title=settings.PROJECT_NAME,
        version=settings.VERSION,
        description="Ajanların Windows ekranındaki elementleri koordinat ve tür bazında çekebilmesini sağlayan lokal robotik süreç arayüzü."
    )

    # CORS Ayarları (Örn: React/Vue frontend bağlanacaksa)
    application.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Rotaları dahil et (/api/v1 prepended)
    application.include_router(api_router, prefix=settings.API_V1_STR)

    return application

app = get_application()

if __name__ == "__main__":
    print("-" * 50)
    print(f"🚀 {settings.PROJECT_NAME} Başlatılıyor...")
    print(f"🌐 Sunucu Adresi: http://localhost:8003")
    print(f"📄 Swagger API Dokümantasyonu: http://localhost:8003/docs")
    print("-" * 50)
    
    uvicorn.run("main:app", host="0.0.0.0", port=8003, reload=True)
