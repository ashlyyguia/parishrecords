from pydantic import BaseModel


class CellModel(BaseModel):
    key: str
    row: int
    x: int
    y: int
    w: int
    h: int


class PageGridModel(BaseModel):
    image_b64: str
    width: int
    height: int
    rows: int
    cols: int
    cells: list[CellModel]


class GridResponse(BaseModel):
    success: bool
    rotation_applied: int
    deskew_deg: float
    pages: dict[str, PageGridModel]
    warnings: list[str]
