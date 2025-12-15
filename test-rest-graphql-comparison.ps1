# test-rest-graphql-comparison.ps1
Write-Host "=== Сравнение REST vs GraphQL запросов ===" -ForegroundColor Cyan
Write-Host ""

# 1. Подготовка данных через REST API
Write-Host "1. ПОДГОТОВКА ТЕСТОВЫХ ДАННЫХ (через REST API)" -ForegroundColor Yellow
Write-Host ""

# Проверяем доступность сервисов
Write-Host "Проверка доступности сервисов..." -ForegroundColor Green

$services = @(
    @{Name="API Gateway"; Url="http://localhost:8080"},
    @{Name="Auth Service"; Url="http://localhost:8080/auth/health"},
    @{Name="Catalog Service"; Url="http://localhost:8080/catalog/health"},
    @{Name="Order Service"; Url="http://localhost:8080/order/health"},
    @{Name="GraphQL Gateway"; Url="http://localhost:8080/graphql/health"}
)

foreach ($service in $services) {
    try {
        $response = Invoke-RestMethod -Uri $service.Url -Method Get -TimeoutSec 3
        Write-Host "✓ $($service.Name): $($response.status)" -ForegroundColor Green
    } catch {
        Write-Host "✗ $($service.Name): Недоступен" -ForegroundColor Red
        Write-Host "  Ошибка: $_" -ForegroundColor DarkRed
        exit 1
    }
}

Write-Host "`nВсе сервисы доступны!" -ForegroundColor Green
Write-Host ""

# 2. Создаем тестового пользователя
Write-Host "2. СОЗДАНИЕ ТЕСТОВОГО ПОЛЬЗОВАТЕЛЯ" -ForegroundColor Yellow

$testUsername = "testuser_$(Get-Random -Minimum 1000 -Maximum 9999)"
$testUserId = $testUsername  # Используем username как user_id для простоты

Write-Host "Имя пользователя: $testUsername" -ForegroundColor Gray

try {
    $userData = @{
        username = $testUsername
        email = "test.$testUsername@example.com"
        password = "TestPassword123!"
        full_name = "Тестовый Пользователь"
    } | ConvertTo-Json

    $registerResponse = Invoke-RestMethod -Uri "http://localhost:8080/auth/api/v1/auth/register" `
        -Method Post `
        -ContentType "application/json" `
        -Body $userData `
        -TimeoutSec 5

    Write-Host "✓ Пользователь создан: $($registerResponse.username)" -ForegroundColor Green
} catch {
    Write-Host "✗ Ошибка создания пользователя: $_" -ForegroundColor Red
    Write-Host "  Попытка использовать существующего пользователя..." -ForegroundColor Yellow
}

# 3. Создаем тестовые товары
Write-Host "`n3. СОЗДАНИЕ ТЕСТОВЫХ ТОВАРОВ" -ForegroundColor Yellow

$createdProducts = @()

try {
    for ($i = 1; $i -le 5; $i++) {
        $productData = @{
            name = "Тестовый товар $i"
            description = "Описание тестового товара номер $i"
            price = (100 + $i * 50)
            category = "electronics"
            stock = 10
            image_url = "https://example.com/product$i.jpg"
        } | ConvertTo-Json

        $productResponse = Invoke-RestMethod -Uri "http://localhost:8080/catalog/api/v1/catalog/items" `
            -Method Post `
            -ContentType "application/json" `
            -Body $productData `
            -TimeoutSec 5

        $createdProducts += $productResponse
        Write-Host "✓ Товар создан: $($productResponse.name) (ID: $($productResponse.id))" -ForegroundColor Green
    }
} catch {
    Write-Host "✗ Ошибка создания товаров: $_" -ForegroundColor Red
    Write-Host "  Используем существующие товары..." -ForegroundColor Yellow
    
    # Пытаемся получить существующие товары
    try {
        $existingProducts = Invoke-RestMethod -Uri "http://localhost:8080/catalog/api/v1/catalog/items?page_size=5" `
            -Method Get `
            -TimeoutSec 5
        
        if ($existingProducts.items.Count -gt 0) {
            $createdProducts = $existingProducts.items[0..([Math]::Min(4, $existingProducts.items.Count-1))]
            Write-Host "  Найдено существующих товаров: $($createdProducts.Count)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  Не удалось получить товары" -ForegroundColor Red
        exit 1
    }
}

if ($createdProducts.Count -eq 0) {
    Write-Host "✗ Нет товаров для тестирования" -ForegroundColor Red
    exit 1
}

Write-Host "`nСоздано товаров: $($createdProducts.Count)" -ForegroundColor Green

# 4. Создаем тестовые заказы
Write-Host "`n4. СОЗДАНИЕ ТЕСТОВЫХ ЗАКАЗОВ" -ForegroundColor Yellow

$createdOrders = @()

for ($orderNum = 1; $orderNum -le 3; $orderNum++) {
    try {
        # Создаем случайные товары для заказа
        $orderItems = @()
        $usedIndices = @()
        
        for ($itemNum = 1; $itemNum -le ([Math]::Min(3, $createdProducts.Count)); $itemNum++) {
            do {
                $productIndex = Get-Random -Minimum 0 -Maximum $createdProducts.Count
            } while ($usedIndices -contains $productIndex)
            
            $usedIndices += $productIndex
            $product = $createdProducts[$productIndex]
            
            $orderItem = @{
                product_id = $product.id
                quantity = (Get-Random -Minimum 1 -Maximum 4)
                price = $product.price
                name = $product.name
            }
            $orderItems += $orderItem
        }
        
        $orderData = @{
            user_id = $testUserId
            items = $orderItems
            shipping_address = @{
                street = "Улица Тестовая $orderNum"
                city = "Тестоград"
                country = "Тестляндия"
                zip_code = "12345$orderNum"
            }
            payment_method = "card"
        } | ConvertTo-Json

        $orderResponse = Invoke-RestMethod -Uri "http://localhost:8080/order/api/v1/orders" `
            -Method Post `
            -ContentType "application/json" `
            -Body $orderData `
            -TimeoutSec 5

        $createdOrders += $orderResponse
        Write-Host "✓ Заказ создан: $($orderResponse.id) (товаров: $($orderItems.Count))" -ForegroundColor Green
        
    } catch {
        Write-Host "✗ Ошибка создания заказа $orderNum: $_" -ForegroundColor Red
    }
}

if ($createdOrders.Count -eq 0) {
    Write-Host "✗ Не удалось создать заказы" -ForegroundColor Red
    exit 1
}

Write-Host "`nСоздано заказов: $($createdOrders.Count)" -ForegroundColor Green
Write-Host ""

# 5. СРАВНЕНИЕ REST vs GraphQL
Write-Host "5. СРАВНЕНИЕ ЗАПРОСОВ: 'Все заказы пользователя с товарами'" -ForegroundColor Yellow
Write-Host "=" * 70

# 5.1 REST подход
Write-Host "`nREST ПОДХОД (несколько отдельных запросов):" -ForegroundColor Magenta
Write-Host "-" * 50

$restMetrics = @{
    TotalRequests = 0
    TotalTimeMs = 0
    TotalDataSize = 0
    OrdersRetrieved = 0
    ItemsRetrieved = 0
}

$restStartTime = Get-Date

try {
    # Запрос 1: Получаем заказы пользователя
    $restMetrics.TotalRequests++
    $userOrders = Invoke-RestMethod -Uri "http://localhost:8080/order/api/v1/orders/user/$testUserId" `
        -Method Get `
        -TimeoutSec 10
    
    $restMetrics.OrdersRetrieved = $userOrders.orders.Count
    $restMetrics.TotalDataSize += (ConvertTo-Json $userOrders).Length
    
    Write-Host "  1. Получено заказов: $($userOrders.orders.Count)" -ForegroundColor Gray
    
    # Для каждого заказа получаем детали товаров
    $allItemsWithDetails = @()
    
    foreach ($order in $userOrders.orders) {
        foreach ($item in $order.items) {
            $restMetrics.TotalRequests++
            $restMetrics.ItemsRetrieved++
            
            try {
                # Запрос 2: Получаем детали каждого товара
                $itemDetails = Invoke-RestMethod -Uri "http://localhost:8080/catalog/api/v1/catalog/items/$($item.product_id)" `
                    -Method Get `
                    -TimeoutSec 5
                
                $itemWithDetails = @{
                    order_id = $order.id
                    order_status = $order.status
                    order_total = $order.total_amount
                    item_name = $item.name
                    item_quantity = $item.quantity
                    item_price = $item.price
                    product_name = $itemDetails.name
                    product_description = $itemDetails.description
                    product_category = $itemDetails.category
                    product_stock = $itemDetails.stock
                }
                $allItemsWithDetails += $itemWithDetails
                
                $restMetrics.TotalDataSize += (ConvertTo-Json $itemDetails).Length
                
            } catch {
                Write-Host "    ✗ Ошибка получения товара $($item.product_id): $_" -ForegroundColor DarkRed
            }
        }
    }
    
} catch {
    Write-Host "  ✗ Ошибка REST запроса: $_" -ForegroundColor Red
}

$restEndTime = Get-Date
$restMetrics.TotalTimeMs = [math]::Round(($restEndTime - $restStartTime).TotalMilliseconds, 2)

# 5.2 GraphQL подход
Write-Host "`nGraphQL ПОДХОД (один комплексный запрос):" -ForegroundColor Magenta
Write-Host "-" * 50

$graphqlMetrics = @{
    TotalRequests = 0
    TotalTimeMs = 0
    TotalDataSize = 0
    OrdersRetrieved = 0
    ItemsRetrieved = 0
}

$graphqlStartTime = Get-Date

try {
    $graphqlMetrics.TotalRequests++
    
    $graphqlQuery = @"
{
  userOrders(userId: "$testUserId") {
    id
    totalAmount
    status
    createdAt
    items {
      productId
      name
      quantity
      price
      product {
        id
        name
        description
        price
        category
        stock
        imageUrl
      }
    }
  }
}
"@

    $graphqlRequest = @{
        query = $graphqlQuery
    } | ConvertTo-Json

    $graphqlResponse = Invoke-RestMethod -Uri "http://localhost:8080/graphql/graphql" `
        -Method Post `
        -ContentType "application/json" `
        -Body $graphqlRequest `
        -TimeoutSec 15

    $graphqlMetrics.TotalDataSize = (ConvertTo-Json $graphqlResponse).Length
    
    if ($graphqlResponse.data.userOrders) {
        $graphqlMetrics.OrdersRetrieved = $graphqlResponse.data.userOrders.Count
        
        foreach ($order in $graphqlResponse.data.userOrders) {
            $graphqlMetrics.ItemsRetrieved += $order.items.Count
        }
    }
    
    Write-Host "  ✓ Получено заказов: $($graphqlMetrics.OrdersRetrieved)" -ForegroundColor Gray
    Write-Host "  ✓ Получено товаров: $($graphqlMetrics.ItemsRetrieved)" -ForegroundColor Gray
    
} catch {
    Write-Host "  ✗ Ошибка GraphQL запроса: $_" -ForegroundColor Red
}

$graphqlEndTime = Get-Date
$graphqlMetrics.TotalTimeMs = [math]::Round(($graphqlEndTime - $graphqlStartTime).TotalMilliseconds, 2)

# 6. ВЫВОД РЕЗУЛЬТАТОВ
Write-Host "`n" + "="*70
Write-Host "6. РЕЗУЛЬТАТЫ СРАВНЕНИЯ" -ForegroundColor Cyan
Write-Host "="*70

Write-Host "`n📊 СТАТИСТИКА ЗАПРОСОВ:" -ForegroundColor Yellow
Write-Host ("{0,-20} {1,-15} {2,-15}" -f "Метрика", "REST", "GraphQL")
Write-Host ("{0,-20} {1,-15} {2,-15}" -f "-------------------", "---------------", "---------------")

Write-Host ("{0,-20} {1,-15} {2,-15}" -f "Время (мс)", $restMetrics.TotalTimeMs, $graphqlMetrics.TotalTimeMs)
Write-Host ("{0,-20} {1,-15} {2,-15}" -f "HTTP запросов", $restMetrics.TotalRequests, $graphqlMetrics.TotalRequests)
Write-Host ("{0,-20} {1,-15} {2,-15}" -f "Заказов", $restMetrics.OrdersRetrieved, $graphqlMetrics.OrdersRetrieved)
Write-Host ("{0,-20} {1,-15} {2,-15}" -f "Товаров", $restMetrics.ItemsRetrieved, $graphqlMetrics.ItemsRetrieved)
Write-Host ("{0,-20} {1,-15} {2,-15}" -f "Данных (байт)", $restMetrics.TotalDataSize, $graphqlMetrics.TotalDataSize)

# Сравнение производительности
Write-Host "`n⚡ АНАЛИЗ ПРОИЗВОДИТЕЛЬНОСТИ:" -ForegroundColor Yellow

if ($restMetrics.TotalTimeMs -gt 0 -and $graphqlMetrics.TotalTimeMs -gt 0) {
    $timeDifference = $restMetrics.TotalTimeMs - $graphqlMetrics.TotalTimeMs
    $timePercentage = [math]::Round(($timeDifference / $restMetrics.TotalTimeMs) * 100, 2)
    
    if ($timeDifference -gt 0) {
        Write-Host "  GraphQL быстрее на $timePercentage% ($timeDifference мс)" -ForegroundColor Green
    } elseif ($timeDifference -lt 0) {
        Write-Host "  REST быстрее на $([math]::Abs($timePercentage))% ($([math]::Abs($timeDifference)) мс)" -ForegroundColor Yellow
    } else {
        Write-Host "  Время выполнения одинаковое" -ForegroundColor Gray
    }
}

# Сравнение эффективности запросов
Write-Host "`n🔗 ЭФФЕКТИВНОСТЬ СЕТЕВЫХ ЗАПРОСОВ:" -ForegroundColor Yellow

$requestEfficiency = [math]::Round(($restMetrics.TotalRequests - $graphqlMetrics.TotalRequests) / $restMetrics.TotalRequests * 100, 2)
Write-Host "  GraphQL сокращает количество HTTP запросов на $requestEfficiency%" -ForegroundColor Green

# Сравнение размера данных
Write-Host "`n💾 ЭФФЕКТИВНОСТЬ ДАННЫХ:" -ForegroundColor Yellow

if ($restMetrics.TotalDataSize -gt 0 -and $graphqlMetrics.TotalDataSize -gt 0) {
    $dataEfficiency = [math]::Round(($restMetrics.TotalDataSize - $graphqlMetrics.TotalDataSize) / $restMetrics.TotalDataSize * 100, 2)
    
    if ($dataEfficiency -gt 0) {
        Write-Host "  GraphQL передает на $dataEfficiency% меньше данных" -ForegroundColor Green
    } elseif ($dataEfficiency -lt 0) {
        Write-Host "  REST передает на $([math]::Abs($dataEfficiency))% меньше данных" -ForegroundColor Yellow
    }
}

# Вывод примеров запросов для документации
Write-Host "`n📝 ПРИМЕРЫ ЗАПРОСОВ ДЛЯ ДОКУМЕНТАЦИИ:" -ForegroundColor Cyan
Write-Host ""

Write-Host "REST API запросы:" -ForegroundColor Magenta
Write-Host "  GET  http://localhost:8080/order/api/v1/orders/user/{user_id}"
Write-Host "  GET  http://localhost:8080/catalog/api/v1/catalog/items/{product_id} (для каждого товара)"
Write-Host ""

Write-Host "GraphQL запрос:" -ForegroundColor Magenta
Write-Host "  POST http://localhost:8080/graphql/graphql"
Write-Host "  Content-Type: application/json"
Write-Host "  Body:"
Write-Host '  {"query": "{ userOrders(userId: \"' + $testUserId + '\") { id totalAmount status items { productId name quantity price product { id name description price category } } } }"}'

# Проверка функциональности GraphQL Playground
Write-Host "`n🎮 GraphQL Playground:" -ForegroundColor Cyan
Write-Host "  Доступен по адресу: http://localhost:8080/graphql/graphql" -ForegroundColor Gray
Write-Host "  Попробуйте выполнить запросы в интерактивной среде" -ForegroundColor Gray

# Очистка тестовых данных (опционально)
Write-Host "`n🧹 ОЧИСТКА ТЕСТОВЫХ ДАННЫХ:" -ForegroundColor Yellow
Write-Host "  Тестовые данные сохранены для дальнейшего тестирования" -ForegroundColor Gray
Write-Host "  Пользователь: $testUsername" -ForegroundColor Gray
Write-Host "  Товары: $($createdProducts.Count) шт" -ForegroundColor Gray
Write-Host "  Заказы: $($createdOrders.Count) шт" -ForegroundColor Gray

Write-Host "`n" + "="*70
Write-Host "✅ ТЕСТИРОВАНИЕ ЗАВЕРШЕНО" -ForegroundColor Green
Write-Host "="*70