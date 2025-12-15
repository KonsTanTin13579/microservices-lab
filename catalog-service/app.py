from fastapi import FastAPI, HTTPException, Query, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional, List, Dict
import uuid
from datetime import datetime
from models import ItemCreate, ItemUpdate, ItemResponse, PaginatedResponse, Category

app = FastAPI(
    title="Catalog Service API",
    description="Сервис управления каталогом товаров",
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

# Временное хранилище товаров
items_db: Dict[str, dict] = {}

# Helper функции
def generate_id():
    return str(uuid.uuid4())

def get_current_time():
    return datetime.utcnow().isoformat()

# REST API Endpoints
@app.get("/api/v1/catalog/items", response_model=PaginatedResponse)
async def get_items(
    category: Optional[Category] = Query(None, description="Фильтр по категории"),
    min_price: Optional[float] = Query(None, ge=0, description="Минимальная цена"),
    max_price: Optional[float] = Query(None, ge=0, description="Максимальная цена"),
    search: Optional[str] = Query(None, description="Поиск по названию или описанию"),
    page: int = Query(1, ge=1, description="Номер страницы"),
    page_size: int = Query(20, ge=1, le=100, description="Размер страницы")
):
    """Получить список товаров с фильтрацией и пагинацией"""
    filtered_items = list(items_db.values())
    
    # Применяем фильтры
    if category:
        filtered_items = [item for item in filtered_items if item["category"] == category.value]
    
    if min_price is not None:
        filtered_items = [item for item in filtered_items if item["price"] >= min_price]
    
    if max_price is not None:
        filtered_items = [item for item in filtered_items if item["price"] <= max_price]
    
    if search:
        search_lower = search.lower()
        filtered_items = [
            item for item in filtered_items
            if search_lower in item["name"].lower() or 
               (item["description"] and search_lower in item["description"].lower())
        ]
    
    # Пагинация
    total = len(filtered_items)
    start = (page - 1) * page_size
    end = start + page_size
    paginated_items = filtered_items[start:end]
    
    return PaginatedResponse(
        items=paginated_items,
        total=total,
        page=page,
        page_size=page_size,
        total_pages=(total + page_size - 1) // page_size
    )

@app.get("/api/v1/catalog/items/{item_id}", response_model=ItemResponse)
async def get_item(item_id: str):
    """Получить товар по ID"""
    item = items_db.get(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return item

@app.post("/api/v1/catalog/items", response_model=ItemResponse, status_code=status.HTTP_201_CREATED)
async def create_item(item: ItemCreate):
    """Создать новый товар"""
    item_id = generate_id()
    current_time = get_current_time()
    
    new_item = {
        "id": item_id,
        "name": item.name,
        "description": item.description,
        "price": item.price,
        "category": item.category.value,
        "stock": item.stock,
        "image_url": item.image_url,
        "created_at": current_time,
        "updated_at": current_time
    }
    
    items_db[item_id] = new_item
    return new_item

@app.put("/api/v1/catalog/items/{item_id}", response_model=ItemResponse)
async def update_item(item_id: str, item_update: ItemUpdate):
    """Обновить товар"""
    if item_id not in items_db:
        raise HTTPException(status_code=404, detail="Item not found")
    
    existing_item = items_db[item_id]
    
    # Обновляем только переданные поля
    update_data = item_update.dict(exclude_unset=True)
    for field, value in update_data.items():
        if field == "category" and value is not None:
            existing_item[field] = value.value
        elif value is not None:
            existing_item[field] = value
    
    existing_item["updated_at"] = get_current_time()
    
    return existing_item

@app.delete("/api/v1/catalog/items/{item_id}")
async def delete_item(item_id: str):
    """Удалить товар"""
    if item_id not in items_db:
        raise HTTPException(status_code=404, detail="Item not found")
    
    deleted_item = items_db.pop(item_id)
    return {"message": f"Item '{deleted_item['name']}' deleted successfully"}

@app.get("/api/v1/catalog/categories")
async def get_categories():
    """Получить список всех категорий"""
    return [
        {"id": cat.value, "name": cat.name, "value": cat.value}
        for cat in Category
    ]

@app.get("/api/v1/catalog/search")
async def search_items(
    q: str = Query(..., min_length=1, description="Поисковый запрос"),
    limit: int = Query(10, ge=1, le=50, description="Лимит результатов")
):
    """Поиск товаров по названию и описанию"""
    query_lower = q.lower()
    results = []
    
    for item in items_db.values():
        if (query_lower in item["name"].lower() or 
            (item["description"] and query_lower in item["description"].lower())):
            results.append(item)
            if len(results) >= limit:
                break
    
    return {"query": q, "results": results, "count": len(results)}

# Старые эндпоинты для обратной совместимости
@app.get("/items", include_in_schema=False)
async def get_items_old():
    return list(items_db.values())

@app.post("/items", include_in_schema=False)
async def create_item_old(item: dict):
    return await create_item(ItemCreate(**item))

# Health check
@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "catalog-service", "item_count": len(items_db)}

@app.get("/")
async def root():
    return {
        "message": "Catalog Service API",
        "docs": "/api/docs",
        "total_items": len(items_db)
    }