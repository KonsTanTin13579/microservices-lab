from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from typing import Dict, Any
import os
from models import PaymentCreate
from payment_gateways import StripeGateway, YooMoneyGateway

app = FastAPI(title="Payment Service", version="1.0.0")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Инициализация платежных шлюзов
stripe_gateway = StripeGateway()
yoomoney_gateway = YooMoneyGateway()

@app.post("/create", response_model=Dict[str, Any])
async def create_payment(payment_data: PaymentCreate):
    """
    Создание платежной сессии
    """
    try:
        if payment_data.payment_method in ["card", "apple_pay", "google_pay"]:
            result = await stripe_gateway.create_payment(payment_data)
            gateway = "stripe"
        elif payment_data.payment_method == "yoomoney":
            result = await yoomoney_gateway.create_payment(payment_data)
            gateway = "yoomoney"
        else:
            raise HTTPException(status_code=400, detail="Unsupported payment method")
        
        return {
            "success": True,
            "gateway": gateway,
            "payment_data": result,
            "order_id": payment_data.order_id
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/{payment_id}/status")
async def get_payment_status(payment_id: str, gateway: str = "stripe"):
    """
    Получение статуса платежа
    """
    try:
        if gateway == "stripe":
            status = await stripe_gateway.get_payment_status(payment_id)
        elif gateway == "yoomoney":
            status = await yoomoney_gateway.get_payment_status(payment_id)
        else:
            raise HTTPException(status_code=400, detail="Invalid gateway")
        
        return {"success": True, "status": status}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/{payment_id}/refund")
async def refund_payment(payment_id: str, amount: float = None, gateway: str = "stripe"):
    """
    Возврат платежа
    """
    try:
        if gateway == "stripe":
            result = await stripe_gateway.refund_payment(payment_id, amount)
        elif gateway == "yoomoney":
            # В реальном проекте - вызов API YooMoney для возврата
            result = {"status": "refund_initiated", "message": "Refund processed"}
        else:
            raise HTTPException(status_code=400, detail="Invalid gateway")
        
        return {"success": True, "refund": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Вебхуки от платежных систем
@app.post("/webhooks/stripe")
async def stripe_webhook(request: Request):
    """
    Обработка вебхуков от Stripe
    """
    payload = await request.body()
    sig_header = request.headers.get("stripe-signature")
    
    try:
        import stripe
        stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
        event = stripe.Webhook.construct_event(
            payload, sig_header, os.getenv("STRIPE_WEBHOOK_SECRET")
        )
        
        if event["type"] == "payment_intent.succeeded":
            payment_intent = event["data"]["object"]
            print(f"Payment succeeded: {payment_intent['id']}")
            # Здесь можно обновить статус в вашей БД
        
        return {"success": True, "event": event["type"]}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/webhooks/yoomoney")
async def yoomoney_webhook(request: Request):
    """
    Обработка вебхуков от YooMoney
    """
    data = await request.json()
    
    notification_type = data.get("notification_type")
    
    if notification_type == "p2p-incoming":
        amount = data.get("amount")
        sender = data.get("sender")
        label = data.get("label")
        
        print(f"YooMoney payment received: {amount} from {sender} for order {label}")
        # Обновление статуса заказа
    
    return {"success": True}

# Health check для Consul
@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "payment-service"}

@app.get("/")
async def root():
    return {"message": "Payment Service is running"}