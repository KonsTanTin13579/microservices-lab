from fastapi import FastAPI, HTTPException, Query, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from typing import List, Optional, Dict, Any
import uuid
from datetime import datetime
from models import OrderCreate, OrderUpdate, OrderResponse, UserOrdersResponse, OrderStatus, PaymentStatus

app = FastAPI(
    title="Order Service API",
    description="Сервис управления заказами",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Временное хранилище заказов
orders_db: Dict[str, dict] = {}

# Helper функции
def generate_order_id():
    return f"ORD-{uuid.uuid4().hex[:8].upper()}"

def get_current_time():
    return datetime.utcnow().isoformat()

def calculate_total(items: List[Dict]) -> float:
    return sum(item["price"] * item["quantity"] for item in items)

# REST API Endpoints
@app.get("/api/v1/orders", response_model=List[OrderResponse])
async def get_orders(
    user_id: Optional[str] = Query(None, description="Фильтр по пользователю"),
    status: Optional[OrderStatus] = Query(None, description="Фильтр по статусу"),
    limit: int = Query(100, ge=1, le=500, description="Лимит результатов")
):
    """Получить список заказов с фильтрацией"""
    filtered_orders = list(orders_db.values())
    
    if user_id:
        filtered_orders = [order for order in filtered_orders if order["user_id"] == user_id]
    
    if status:
        filtered_orders = [order for order in filtered_orders if order["status"] == status.value]
    
    return filtered_orders[:limit]

@app.get("/api/v1/orders/{order_id}", response_model=OrderResponse)
async def get_order(order_id: str):
    """Получить заказ по ID"""
    order = orders_db.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return order

@app.get("/api/v1/orders/user/{user_id}", response_model=UserOrdersResponse)
async def get_user_orders(
    user_id: str,
    status: Optional[OrderStatus] = Query(None, description="Фильтр по статусу"),
    limit: int = Query(50, ge=1, le=200, description="Лимит результатов")
):
    """Получить все заказы пользователя"""
    user_orders = [order for order in orders_db.values() if order["user_id"] == user_id]
    
    if status:
        user_orders = [order for order in user_orders if order["status"] == status.value]
    
    return UserOrdersResponse(
        orders=user_orders[:limit],
        total=len(user_orders),
        user_id=user_id
    )

@app.post("/api/v1/orders", response_model=OrderResponse, status_code=status.HTTP_201_CREATED)
async def create_order(order_data: OrderCreate):
    """Создать новый заказ"""
    order_id = generate_order_id()
    current_time = get_current_time()
    
    # Рассчитываем общую сумму
    items_dict = [item.dict() for item in order_data.items]
    total_amount = calculate_total(items_dict)
    
    new_order = {
        "id": order_id,
        "user_id": order_data.user_id,
        "items": items_dict,
        "total_amount": total_amount,
        "status": OrderStatus.PENDING.value,
        "payment_status": PaymentStatus.PENDING.value,
        "shipping_address": order_data.shipping_address,
        "payment_method": order_data.payment_method,
        "tracking_number": None,
        "notes": None,
        "created_at": current_time,
        "updated_at": current_time
    }
    
    orders_db[order_id] = new_order
    return new_order

@app.put("/api/v1/orders/{order_id}", response_model=OrderResponse)
async def update_order(order_id: str, order_update: OrderUpdate):
    """Обновить заказ"""
    if order_id not in orders_db:
        raise HTTPException(status_code=404, detail="Order not found")
    
    order = orders_db[order_id]
    
    # Обновляем только переданные поля
    update_data = order_update.dict(exclude_unset=True)
    for field, value in update_data.items():
        if value is not None:
            if hasattr(value, 'value'):
                order[field] = value.value
            else:
                order[field] = value
    
    order["updated_at"] = get_current_time()
    
    return order

@app.delete("/api/v1/orders/{order_id}")
async def delete_order(order_id: str):
    """Удалить заказ"""
    if order_id not in orders_db:
        raise HTTPException(status_code=404, detail="Order not found")
    
    deleted_order = orders_db.pop(order_id)
    return {"message": f"Order {order_id} deleted successfully"}

@app.get("/api/v1/orders/{order_id}/items")
async def get_order_items(order_id: str):
    """Получить товары из заказа"""
    order = orders_db.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    
    return {
        "order_id": order_id,
        "items": order["items"],
        "total_items": len(order["items"]),
        "total_amount": order["total_amount"]
    }

# Health check
@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "order-service",
        "order_count": len(orders_db)
    }

@app.get("/")
async def root():
    return {
        "message": "Order Service API",
        "docs": "/api/docs",
        "total_orders": len(orders_db)
    }