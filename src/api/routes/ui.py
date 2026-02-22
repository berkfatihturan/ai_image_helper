from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
import os
import json

from src.core.config import settings
from src.services.extractor import extract_windows_ui, get_os_type
from src.services.visualizer import draw_ui_map
from src.models.schemas import ExtractionResponse

router = APIRouter()

@router.get("/extract", response_model=ExtractionResponse)
def extract_ui_elements():
    """
    O anki Windows ekranını tarar, tüm UI elemanlarını ve
    sadece görünenleri hesaplayarak (Map-Reduce OCCLUSION) JSON objesi olarak döndürür.
    Aynı zamanda sunucu tarafında harita resmini (ui_map_visual.png) günceller.
    """
    os_type = get_os_type()
    if os_type != "Windows":
        raise HTTPException(status_code=400, detail="Bu sunucu sadece Windows işletim sisteminde çalışır.")
        
    try:
        all_elements, visible_elements = extract_windows_ui()
        
        # Resmi arka planda güncelleyelim ki /map endpointinden çekilebilsin
        if visible_elements:
            draw_ui_map(visible_elements, output_path=settings.MAP_OUTPUT_FILE)
            
            # Disk persistency (Eski sistem uyumluluğu için JSON kaydet)
            json_all = json.dumps(all_elements, ensure_ascii=False, indent=2)
            json_visible = json.dumps(visible_elements, ensure_ascii=False, indent=2)
            with open(settings.JSON_ALL_FILE, "w", encoding="utf-8") as f:
                f.write(json_all)
            with open(settings.JSON_VISIBLE_FILE, "w", encoding="utf-8") as f:
                f.write(json_visible)
            
        return dict(
            status="success",
            message="Windows ekran UI elementleri başarıyla tarandı.",
            data=dict(
                visible_elements=visible_elements,
                all_elements=all_elements
            )
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"API Hatası (Extraction): {str(e)}")

@router.get("/map")
def get_visual_map():
    """
    En son çıkarılan UI elemanlarının görsel (PNG) haritasını döndürür.
    Eğer henüz tarama yapılmadıysa hata verir.
    """
    if not os.path.exists(settings.MAP_OUTPUT_FILE):
        raise HTTPException(
            status_code=404, 
            detail="Harita bulunamadı. Lütfen önce /api/v1/ui/extract endpointine istek atın."
        )
        
    return FileResponse(settings.MAP_OUTPUT_FILE, media_type="image/png", filename="ui_map_visual.png")
