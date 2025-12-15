# test-compare.ps1 - REST vs GraphQL Comparison Test
Write-Host "=== REST vs GraphQL Comparison Test ===" -ForegroundColor Cyan
Write-Host ""

# 1. Test setup
Write-Host "1. SETUP TEST DATA" -ForegroundColor Yellow

# Check services
Write-Host "Checking services..." -ForegroundColor Green

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
        Write-Host "  OK: $($service.Name) - $($response.status)" -ForegroundColor Green
    } catch {
        Write-Host "  ERROR: $($service.Name) - Not available" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`nAll services are available!" -ForegroundColor Green
Write-Host ""

# 2. Create test user
Write-Host "2. CREATE TEST USER" -ForegroundColor Yellow

$testUsername = "testuser_$(Get-Random -Minimum 1000 -Maximum 9999)"
$testUserId = $testUsername

Write-Host "Username: $testUsername" -ForegroundColor Gray

try {
    $userData = @{
        username = $testUsername
        email = "test.$testUsername@example.com"
        password = "Test123!"
        full_name = "Test User"
    } | ConvertTo-Json

    $registerResponse = Invoke-RestMethod -Uri "http://localhost:8080/auth/api/v1/auth/register" `
        -Method Post `
        -ContentType "application/json" `
        -Body $userData `
        -TimeoutSec 5

    Write-Host "  OK: User created - $($registerResponse.username)" -ForegroundColor Green
} catch {
    Write-Host "  WARNING: User creation error: $_" -ForegroundColor Yellow
    Write-Host "  Using existing user..." -ForegroundColor Gray
}

# 3. Create or get test products
Write-Host "`n3. GET TEST PRODUCTS" -ForegroundColor Yellow

$testProducts = @()

try {
    # Try to get existing products
    $productsResponse = Invoke-RestMethod -Uri "http://localhost:8080/catalog/api/v1/catalog/items?page_size=5" `
        -Method Get `
        -TimeoutSec 5
    
    if ($productsResponse.items.Count -gt 0) {
        $testProducts = $productsResponse.items[0..([Math]::Min(4, $productsResponse.items.Count-1))]
        Write-Host "  OK: Found existing products - $($testProducts.Count) items" -ForegroundColor Green
    } else {
        # Create test products if none exist
        Write-Host "  Creating test products..." -ForegroundColor Gray
        
        for ($i = 1; $i -le 3; $i++) {
            $productData = @{
                name = "Test Product $i"
                description = "Description for test product $i"
                price = (100 + $i * 50)
                category = "electronics"
                stock = 10
            } | ConvertTo-Json

            $productResponse = Invoke-RestMethod -Uri "http://localhost:8080/catalog/api/v1/catalog/items" `
                -Method Post `
                -ContentType "application/json" `
                -Body $productData `
                -TimeoutSec 5

            $testProducts += $productResponse
        }
        Write-Host "  OK: Created test products - $($testProducts.Count) items" -ForegroundColor Green
    }
} catch {
    Write-Host "  ERROR: Cannot get or create products: $_" -ForegroundColor Red
    exit 1
}

if ($testProducts.Count -eq 0) {
    Write-Host "  ERROR: No products available for testing" -ForegroundColor Red
    exit 1
}

# 4. Create test order
Write-Host "`n4. CREATE TEST ORDER" -ForegroundColor Yellow

$testOrderId = $null

try {
    $orderItems = @()
    
    # Add 2 random products to order
    $randomProducts = $testProducts | Get-Random -Count ([Math]::Min(2, $testProducts.Count))
    
    foreach ($product in $randomProducts) {
        $orderItem = @{
            product_id = $product.id
            quantity = (Get-Random -Minimum 1 -Maximum 3)
            price = $product.price
            name = $product.name
        }
        $orderItems += $orderItem
    }
    
    $orderData = @{
        user_id = $testUserId
        items = $orderItems
        shipping_address = @{
            street = "Test Street 123"
            city = "Test City"
            country = "Test Country"
            zip_code = "123456"
        }
        payment_method = "card"
    } | ConvertTo-Json

    $orderResponse = Invoke-RestMethod -Uri "http://localhost:8080/order/api/v1/orders" `
        -Method Post `
        -ContentType "application/json" `
        -Body $orderData `
        -TimeoutSec 5

    $testOrderId = $orderResponse.id
    Write-Host "  OK: Order created - ID: $testOrderId" -ForegroundColor Green
    Write-Host "      Items: $($orderItems.Count), Total: $($orderResponse.total_amount)" -ForegroundColor Gray
    
} catch {
    Write-Host "  WARNING: Order creation error: $_" -ForegroundColor Yellow
    Write-Host "  Using existing orders for testing..." -ForegroundColor Gray
}

# 5. REST vs GraphQL COMPARISON
Write-Host "`n" + "="*60
Write-Host "5. REST vs GRAPHQL COMPARISON" -ForegroundColor Cyan
Write-Host "="*60
Write-Host ""

# 5.1 REST Approach
Write-Host "REST APPROACH (Multiple requests):" -ForegroundColor Magenta
Write-Host "-"*40

$restMetrics = @{
    StartTime = Get-Date
    TotalRequests = 0
    TotalTimeMs = 0
    TotalDataSize = 0
    OrdersRetrieved = 0
    ItemsRetrieved = 0
}

try {
    # Request 1: Get user orders
    $restMetrics.TotalRequests++
    $userOrders = Invoke-RestMethod -Uri "http://localhost:8080/order/api/v1/orders/user/$testUserId" `
        -Method Get `
        -TimeoutSec 10
    
    $restMetrics.OrdersRetrieved = if ($userOrders.orders) { $userOrders.orders.Count } else { 0 }
    $restMetrics.TotalDataSize += (ConvertTo-Json $userOrders).Length
    
    Write-Host "  Request 1: Get user orders" -ForegroundColor Gray
    Write-Host "    Orders found: $($restMetrics.OrdersRetrieved)" -ForegroundColor Gray
    
    # Request 2-N: Get details for each product in each order
    if ($userOrders.orders -and $userOrders.orders.Count -gt 0) {
        foreach ($order in $userOrders.orders) {
            foreach ($item in $order.items) {
                $restMetrics.TotalRequests++
                $restMetrics.ItemsRetrieved++
                
                try {
                    $itemDetails = Invoke-RestMethod -Uri "http://localhost:8080/catalog/api/v1/catalog/items/$($item.product_id)" `
                        -Method Get `
                        -TimeoutSec 3
                    
                    $restMetrics.TotalDataSize += (ConvertTo-Json $itemDetails).Length
                    
                } catch {
                    # Skip if product details not available
                }
            }
        }
    }
    
    Write-Host "  Total REST requests: $($restMetrics.TotalRequests)" -ForegroundColor Gray
    Write-Host "  Products retrieved: $($restMetrics.ItemsRetrieved)" -ForegroundColor Gray
    
} catch {
    Write-Host "  ERROR: REST request failed: $_" -ForegroundColor Red
}

$restMetrics.TotalTimeMs = [math]::Round(((Get-Date) - $restMetrics.StartTime).TotalMilliseconds, 2)

# 5.2 GraphQL Approach
Write-Host "`nGRAPHQL APPROACH (Single request):" -ForegroundColor Magenta
Write-Host "-"*40

$graphqlMetrics = @{
    StartTime = Get-Date
    TotalRequests = 0
    TotalTimeMs = 0
    TotalDataSize = 0
    OrdersRetrieved = 0
    ItemsRetrieved = 0
}

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
            $graphqlMetrics.ItemsRetrieved += if ($order.items) { $order.items.Count } else { 0 }
        }
    }
    
    Write-Host "  Request 1: GraphQL query" -ForegroundColor Gray
    Write-Host "    Orders found: $($graphqlMetrics.OrdersRetrieved)" -ForegroundColor Gray
    Write-Host "    Products in response: $($graphqlMetrics.ItemsRetrieved)" -ForegroundColor Gray
    
} catch {
    Write-Host "  ERROR: GraphQL request failed: $_" -ForegroundColor Red
}

$graphqlMetrics.TotalTimeMs = [math]::Round(((Get-Date) - $graphqlMetrics.StartTime).TotalMilliseconds, 2)

# 6. RESULTS
Write-Host "`n" + "="*60
Write-Host "6. COMPARISON RESULTS" -ForegroundColor Cyan
Write-Host "="*60
Write-Host ""

Write-Host "PERFORMANCE METRICS:" -ForegroundColor Yellow
Write-Host ("{0,-20} {1,-15} {2,-15}" -f "Metric", "REST", "GraphQL")
Write-Host ("{0,-20} {1,-15} {2,-15}" -f "-------------------", "---------------", "---------------")

Write-Host ("{0,-20} {1,-15} {2,-15}" -f "Time (ms)", $restMetrics.TotalTimeMs, $graphqlMetrics.TotalTimeMs)
Write-Host ("{0,-20} {1,-15} {2,-15}" -f "HTTP Requests", $restMetrics.TotalRequests, $graphqlMetrics.TotalRequests)
Write-Host ("{0,-20} {1,-15} {2,-15}" -f "Orders", $restMetrics.OrdersRetrieved, $graphqlMetrics.OrdersRetrieved)
Write-Host ("{0,-20} {1,-15} {2,-15}" -f "Products", $restMetrics.ItemsRetrieved, $graphqlMetrics.ItemsRetrieved)
Write-Host ("{0,-20} {1,-15} {2,-15}" -f "Data Size (bytes)", $restMetrics.TotalDataSize, $graphqlMetrics.TotalDataSize)

# Analysis
Write-Host "`nANALYSIS:" -ForegroundColor Yellow

if ($restMetrics.TotalTimeMs -gt 0 -and $graphqlMetrics.TotalTimeMs -gt 0) {
    $timeDiff = $restMetrics.TotalTimeMs - $graphqlMetrics.TotalTimeMs
    $timePercent = [math]::Round(($timeDiff / $restMetrics.TotalTimeMs) * 100, 2)
    
    if ($timeDiff -gt 0) {
        Write-Host "  GraphQL is $timePercent% faster ($timeDiff ms)" -ForegroundColor Green
    } elseif ($timeDiff -lt 0) {
        Write-Host "  REST is $([math]::Abs($timePercent))% faster ($([math]::Abs($timeDiff)) ms)" -ForegroundColor Yellow
    } else {
        Write-Host "  Same execution time" -ForegroundColor Gray
    }
}

if ($restMetrics.TotalRequests -gt 0) {
    $requestReduction = [math]::Round(($restMetrics.TotalRequests - $graphqlMetrics.TotalRequests) / $restMetrics.TotalRequests * 100, 2)
    Write-Host "  GraphQL reduces HTTP requests by $requestReduction%" -ForegroundColor Green
}

# Example queries for documentation
Write-Host "`nEXAMPLE QUERIES:" -ForegroundColor Cyan
Write-Host ""

Write-Host "REST API:" -ForegroundColor Magenta
Write-Host "  GET  http://localhost:8080/order/api/v1/orders/user/$testUserId"
Write-Host "  GET  http://localhost:8080/catalog/api/v1/catalog/items/{product_id}"
Write-Host ""

Write-Host "GraphQL:" -ForegroundColor Magenta
Write-Host "  POST http://localhost:8080/graphql/graphql"
Write-Host '  Body: {"query": "{ userOrders(userId: \"' + $testUserId + '\") { id totalAmount status items { productId name quantity price product { id name description price } } } }"}'
Write-Host ""

Write-Host "GraphQL Playground:" -ForegroundColor Cyan
Write-Host "  http://localhost:8080/graphql/graphql" -ForegroundColor Gray

Write-Host "`n" + "="*60
Write-Host "TEST COMPLETED" -ForegroundColor Green
Write-Host "="*60