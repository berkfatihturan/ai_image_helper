from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "Windows UI Extraction API"
    VERSION: str = "1.0.0"
    API_V1_STR: str = "/api/v1"
    
    # Her tarama sonrası oluşturulan dosya yolları
    MAP_OUTPUT_FILE: str = "ui_map_visual.png"
    JSON_ALL_FILE: str = "ui_output_all.json"
    JSON_VISIBLE_FILE: str = "ui_output_visible.json"
    
    # Extraction Limitleri
    MAX_ELEMENTS_TO_PARSE: int = 4000
    
    class Config:
        case_sensitive = True

settings = Settings()
