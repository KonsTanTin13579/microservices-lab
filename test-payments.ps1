# test-payment.ps1
Write-Host "Testing Payment Service..." -ForegroundColor Green

# Тест health check
Write-Host "`n1. Testing health check:" -ForegroundColor Yellow
Invoke-RestMethod -Uri "http://localhost:5003/health" -Method Get

# Тест создания платежа через Stripe
Write-Host "`n2. Testing Stripe payment creation:" -ForegroundColor Yellow
$paymentData = @{
    order_id = "order_123"
    user_id = "user_456"
    amount = 1000
    currency = "RUB"
    payment_method = "card"
    description = "Test payment"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:5003/create" `
    -Method Post `
    -ContentType "application/json" `
    -Body $paymentData

# Тест создания платежа через YooMoney
Write-Host "`n3. Testing YooMoney payment creation:" -ForegroundColor Yellow
$yoomoneyData = @{
    order_id = "order_124"
    user_id = "user_457"
    amount = 500
    currency = "RUB"
    payment_method = "yoomoney"
    description = "YooMoney test"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:5003/create" `
    -Method Post `
    -ContentType "application/json" `
    -Body $yoomoneyData

# Тест через API Gateway (nginx)
Write-Host "`n4. Testing through API Gateway (nginx):" -ForegroundColor Yellow
Invoke-RestMethod -Uri "http://localhost:8080/payment/health" -Method Get

Write-Host "`nPayment Service tests completed!" -ForegroundColor Green