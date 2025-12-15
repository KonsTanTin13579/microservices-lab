from fastapi import FastAPI, HTTPException, Depends, status, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.docs import get_swagger_ui_html
from fastapi.openapi.utils import get_openapi
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime, timedelta
import jwt
import hashlib
import re

app = FastAPI(
    title="Auth Service API",
    description="Сервис аутентификации и управления пользователями",
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

# Конфигурация
SECRET_KEY = "your-secret-key-change-this-in-production"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

# Временная "база данных"
fake_users_db = {}
fake_profiles_db = {}

# Простая валидация email
def validate_email(email: str) -> str:
    pattern = r'^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$'
    if not re.match(pattern, email):
        raise ValueError("Invalid email format")
    return email

# Pydantic модели
class UserRegister(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    email: str = Field(..., description="Email address")
    password: str = Field(..., min_length=6)
    full_name: Optional[str] = Field(None, max_length=100)

class UserLogin(BaseModel):
    username: str
    password: str

class Token(BaseModel):
    access_token: str
    token_type: str
    expires_in: int

class UserProfile(BaseModel):
    username: str
    email: str
    full_name: Optional[str] = None
    created_at: str
    updated_at: str

class UserUpdate(BaseModel):
    email: Optional[str] = None
    full_name: Optional[str] = None
    password: Optional[str] = None

# Функции для работы с паролями и JWT
def get_password_hash(password):
    if len(password.encode('utf-8')) > 72:
        password = hashlib.sha256(password.encode('utf-8')).hexdigest()
    from passlib.context import CryptContext
    pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    return pwd_context.hash(password)

def verify_password(plain_password, hashed_password):
    if len(plain_password.encode('utf-8')) > 72:
        plain_password = hashlib.sha256(plain_password.encode('utf-8')).hexdigest()
    from passlib.context import CryptContext
    pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    return pwd_context.verify(plain_password, hashed_password)

def create_access_token(data: dict, expires_delta: timedelta = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire, "iat": datetime.utcnow()})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def verify_token(token: str):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")

async def get_current_user(authorization: str = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Not authenticated")
    
    token = authorization.split(" ")[1]
    payload = verify_token(token)
    username = payload.get("sub")
    
    if username not in fake_users_db:
        raise HTTPException(status_code=401, detail="User not found")
    
    return username

# REST API Endpoints
@app.post("/api/v1/auth/register", status_code=status.HTTP_201_CREATED)
async def register(user: UserRegister):
    """Регистрация нового пользователя"""
    try:
        # Валидируем email
        validate_email(user.email)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid email format")
    
    if user.username in fake_users_db:
        raise HTTPException(status_code=400, detail="Username already registered")
    
    hashed_password = get_password_hash(user.password)
    current_time = datetime.utcnow().isoformat()
    
    fake_users_db[user.username] = {
        "username": user.username,
        "email": user.email,
        "hashed_password": hashed_password,
        "created_at": current_time,
        "updated_at": current_time
    }
    
    fake_profiles_db[user.username] = {
        "full_name": user.full_name,
        "created_at": current_time,
        "updated_at": current_time
    }
    
    return {"message": "User registered successfully", "username": user.username}

@app.post("/api/v1/auth/login", response_model=Token)
async def login(user: UserLogin):
    """Аутентификация пользователя"""
    user_data = fake_users_db.get(user.username)
    if not user_data or not verify_password(user.password, user_data["hashed_password"]):
        raise HTTPException(status_code=401, detail="Incorrect username or password")
    
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.username, "email": user_data["email"]},
        expires_delta=access_token_expires
    )
    
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "expires_in": ACCESS_TOKEN_EXPIRE_MINUTES * 60
    }

@app.get("/api/v1/auth/profile", response_model=UserProfile)
async def get_profile(current_user: str = Depends(get_current_user)):
    """Получение профиля пользователя"""
    user_data = fake_users_db.get(current_user)
    profile_data = fake_profiles_db.get(current_user)
    
    if not user_data or not profile_data:
        raise HTTPException(status_code=404, detail="User not found")
    
    return {
        "username": user_data["username"],
        "email": user_data["email"],
        "full_name": profile_data["full_name"],
        "created_at": user_data["created_at"],
        "updated_at": user_data["updated_at"]
    }

@app.put("/api/v1/auth/profile")
async def update_profile(
    update_data: UserUpdate,
    current_user: str = Depends(get_current_user)
):
    """Обновление профиля пользователя"""
    if current_user not in fake_users_db:
        raise HTTPException(status_code=404, detail="User not found")
    
    user_data = fake_users_db[current_user]
    profile_data = fake_profiles_db[current_user]
    current_time = datetime.utcnow().isoformat()
    
    # Обновляем email если передан
    if update_data.email:
        try:
            validate_email(update_data.email)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid email format")
        user_data["email"] = update_data.email
    
    # Обновляем пароль если передан
    if update_data.password:
        user_data["hashed_password"] = get_password_hash(update_data.password)
    
    # Обновляем полное имя если передано
    if update_data.full_name is not None:
        profile_data["full_name"] = update_data.full_name
    
    user_data["updated_at"] = current_time
    profile_data["updated_at"] = current_time
    
    return {"message": "Profile updated successfully"}

@app.post("/api/v1/auth/logout")
async def logout(current_user: str = Depends(get_current_user)):
    """Выход из системы (на клиенте токен удаляется)"""
    return {"message": "Successfully logged out"}

@app.get("/api/v1/auth/verify")
async def verify_token_endpoint(token: str):
    """Проверка валидности токена"""
    payload = verify_token(token)
    return {
        "username": payload.get("sub"),
        "email": payload.get("email"),
        "valid": True,
        "expires_at": datetime.fromtimestamp(payload["exp"]).isoformat()
    }

# Старые эндпоинты для обратной совместимости
@app.post("/register", include_in_schema=False)
async def register_old(user: dict):
    return await register(UserRegister(**user))

@app.post("/login", include_in_schema=False)
async def login_old(user: dict):
    return await login(UserLogin(**user))

# Health check
@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "auth-service"}

@app.get("/")
async def root():
    return {"message": "Auth Service API", "docs": "/api/docs"}