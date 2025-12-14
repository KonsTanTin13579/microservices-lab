import stripe
import uuid
from typing import Dict, Any, Optional
import os
from models import PaymentCreate

class StripeGateway:
    def __init__(self):
        self.stripe_api_key = os.getenv("STRIPE_SECRET_KEY", "sk_test_xxx")
        stripe.api_key = self.stripe_api_key
    
    async def create_payment(self, payment_data: PaymentCreate) -> Dict[str, Any]:
        """Создание платежа в Stripe"""
        try:
            payment_intent = stripe.PaymentIntent.create(
                amount=int(payment_data.amount * 100),
                currency=payment_data.currency.lower(),
                metadata={
                    "order_id": payment_data.order_id,
                    "user_id": payment_data.user_id,
                    **(payment_data.metadata or {})
                },
                description=payment_data.description,
                automatic_payment_methods={"enabled": True},
            )
            
            return {
                "payment_id": payment_intent.id,
                "client_secret": payment_intent.client_secret,
                "status": payment_intent.status,
                "amount": payment_intent.amount / 100,
                "currency": payment_intent.currency
            }
        except Exception as e:
            raise Exception(f"Stripe error: {str(e)}")
    
    async def get_payment_status(self, payment_id: str) -> Dict[str, Any]:
        """Получение статуса платежа"""
        try:
            payment_intent = stripe.PaymentIntent.retrieve(payment_id)
            return {
                "id": payment_intent.id,
                "status": payment_intent.status,
                "amount": payment_intent.amount / 100,
                "metadata": payment_intent.metadata
            }
        except Exception as e:
            raise Exception(f"Stripe error: {str(e)}")
    
    async def refund_payment(self, payment_id: str, amount: Optional[float] = None) -> Dict[str, Any]:
        """Возврат платежа"""
        try:
            refund_params = {"payment_intent": payment_id}
            if amount:
                refund_params["amount"] = int(amount * 100)
            
            refund = stripe.Refund.create(**refund_params)
            return {
                "refund_id": refund.id,
                "status": refund.status,
                "amount": refund.amount / 100
            }
        except Exception as e:
            raise Exception(f"Stripe refund error: {str(e)}")

class YooMoneyGateway:
    def __init__(self):
        self.receiver_wallet = os.getenv("YOOMONEY_WALLET", "410011111111111")
    
    async def create_payment(self, payment_data: PaymentCreate) -> Dict[str, Any]:
        """Создание платежа в YooMoney"""
        payment_id = str(uuid.uuid4())
        
        # Формируем ссылку для оплаты через YooMoney
        payment_url = f"https://yoomoney.ru/quickpay/confirm.xml?receiver={self.receiver_wallet}&quickpay-form=shop&sum={payment_data.amount}&label={payment_id}"
        
        return {
            "payment_id": payment_id,
            "payment_url": payment_url,
            "status": "pending",
            "amount": payment_data.amount,
            "currency": payment_data.currency
        }
    
    async def get_payment_status(self, payment_id: str) -> Dict[str, Any]:
        """Получение статуса платежа"""
        # В реальном проекте - вызов API YooMoney для проверки статуса
        return {
            "payment_id": payment_id,
            "status": "pending",  # Заглушка для демо
            "message": "Check YooMoney wallet for actual status"
        }