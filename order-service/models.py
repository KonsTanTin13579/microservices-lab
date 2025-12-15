from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from datetime import datetime
from enum import Enum

class OrderStatus(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    SHIPPED = "shipped"
    DELIVERED = "delivered"
    CANCELLED = "cancelled"
    REFUNDED = "refunded"

class PaymentStatus(str, Enum):
    PENDING = "pending"
    PAID = "paid"
    FAILED = "failed"
    REFUNDED = "refunded"

class OrderItem(BaseModel):
    product_id: str = Field(..., description="ID товара из Catalog Service")
    quantity: int = Field(..., gt=0, description="Количество")
    price: float = Field(..., gt=0, description="Цена за единицу")
    name: str = Field(..., description="Название товара")

class OrderCreate(BaseModel):
    user_id: str = Field(..., description="ID пользователя")
    items: List[OrderItem] = Field(..., min_items=1, description="Список товаров")
    shipping_address: Dict[str, Any] = Field(..., description="Адрес доставки")
    payment_method: str = Field(default="card", description="Метод оплаты")

class OrderUpdate(BaseModel):
    status: Optional[OrderStatus] = None
    payment_status: Optional[PaymentStatus] = None
    tracking_number: Optional[str] = None
    notes: Optional[str] = None

class OrderResponse(BaseModel):
    id: str
    user_id: str
    items: List[OrderItem]
    total_amount: float
    status: OrderStatus
    payment_status: PaymentStatus
    shipping_address: Dict[str, Any]
    payment_method: str
    tracking_number: Optional[str]
    notes: Optional[str]
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True

class UserOrdersResponse(BaseModel):
    orders: List[OrderResponse]
    total: int
    user_id: str