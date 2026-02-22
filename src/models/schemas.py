from typing import List, Dict, Any, Optional
from pydantic import BaseModel

class Coordinate(BaseModel):
    x: int
    y: int
    genislik: int
    yukseklik: int

class CenterCoordinate(BaseModel):
    x: int
    y: int

class UIElement(BaseModel):
    tip: str
    isim: str
    koordinat: Coordinate
    merkez_koordinat: CenterCoordinate

class WindowGroup(BaseModel):
    pencere: str
    z_index: int
    renk: List[int]  # [R, G, B]
    kutu: List[int]  # [x1, y1, x2, y2]
    elmanlar: List[UIElement]

class ExtractionResponseData(BaseModel):
    visible_elements: List[WindowGroup]
    all_elements: List[WindowGroup]

class ExtractionResponse(BaseModel):
    status: str
    message: str
    data: ExtractionResponseData
