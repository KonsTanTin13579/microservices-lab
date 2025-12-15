from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
from enum import Enum

class Category(str, Enum):
    ELECTRONICS = "electronics"
    BOOKS = "books"
    CLOTHING = "clothing"
    FOOD = "food"
    OTHER = "other"

class ItemCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100, description="Название товара")
    description: Optional[str] = Field(None, max_length=500, description="Описание товара")
    price: float = Field(..., gt=0, description="Цена товара")
    category: Category = Field(default=Category.OTHER, description="Категория товара")
    stock: int = Field(default=1, ge=0, description="Количество на складе")
    image_url: Optional[str] = Field(None, description="URL изображения товара")

class ItemUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=500)
    price: Optional[float] = Field(None, gt=0)
    category: Optional[Category] = None
    stock: Optional[int] = Field(None, ge=0)
    image_url: Optional[str] = None

class ItemResponse(BaseModel):
    id: str
    name: str
    description: Optional[str]
    price: float
    category: str
    stock: int
    image_url: Optional[str]
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True

class PaginatedResponse(BaseModel):
    items: List[ItemResponse]
    total: int
    page: int
    page_size: int
    total_pages: int