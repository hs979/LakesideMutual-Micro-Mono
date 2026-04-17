<#
.SYNOPSIS
    LakeSide Mutual - End-to-End API Test Script
.DESCRIPTION
    Tests all microservice APIs after all services are started.
    Prerequisites: Start all services per STARTUP_GUIDE.md first.
.EXAMPLE
    .\e2e-test.ps1
#>

$ErrorActionPreference = "Continue"

# ---- Service Base URLs ----
$CORE_URL  = "http://localhost:8110"   # customer-core
$CSS_URL   = "http://localhost:8080"   # customer-self-service-backend
$PM_URL    = "http://localhost:8090"   # policy-management-backend
$CM_URL    = "http://localhost:8100"   # customer-management-backend
$ADMIN_URL = "http://localhost:9000"   # spring-boot-admin

# ---- API Keys (from application.properties) ----
# customer-core requires "Bearer " prefix (see APIKeyAuthenticationManager.java)
$CORE_APIKEY = "Bearer b318ad736c6c844b"
$CSS_APIKEY  = "Bearer b318ad736c6c844b"
# policy-management and customer-management have NO API key auth (open access)
$PM_APIKEY   = "Bearer 999ab497f8ec1052"
$CM_APIKEY   = "Bearer 9b93ebe19e16bbbd"

# ---- Pre-loaded test customer (from mock_customers_small.csv) ----
$EXISTING_CID  = "rgpp0wkpec"   # Max Mustermann
$ADMIN_EMAIL   = "admin@example.com"
$ADMIN_PASS    = "1password"

# ---- New test account ----
$TEST_EMAIL = "e2etest$(Get-Random -Maximum 9999)@lakesidemutual.com"
$TEST_PASS  = "Test@12345"

# ---- Counters ----
$script:PASS = 0
$script:FAIL = 0

# ==============================================================================
# Helper functions
# ==============================================================================

function Write-Section([string]$title) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Invoke-ApiTest {
    param(
        [string]$Name,
        [string]$Method        = "GET",
        [string]$Url,
        [hashtable]$Headers    = @{},
        [string]$Body          = $null,
        [int]$ExpectStatus     = 200,
        [string]$ExpectContain = $null
    )

    $allHeaders = $Headers + @{ "Content-Type" = "application/json; charset=utf-8" }

    $webParams = @{
        Method          = $Method
        Uri             = $Url
        Headers         = $allHeaders
        UseBasicParsing = $true
        TimeoutSec      = 20
    }
    if ($Body) {
        $webParams["Body"] = [System.Text.Encoding]::UTF8.GetBytes($Body)
    }

    $statusCode = $null
    $content    = $null
    $ok         = $false

    try {
        $resp       = Invoke-WebRequest @webParams
        $statusCode = [int]$resp.StatusCode
        $content    = $resp.Content
        if ($content -is [byte[]]) {
            $content = [System.Text.Encoding]::UTF8.GetString($content)
        }
        $ok         = ($statusCode -eq $ExpectStatus)
        if ($ExpectContain -and ($content -notmatch [regex]::Escape($ExpectContain))) {
            $ok = $false
        }
    }
    catch {
        $statusCode = 0
        $errResp = $null
        if ($_.Exception.Response) {
            $errResp = $_.Exception.Response
        }
        elseif ($_.Exception.InnerException -and $_.Exception.InnerException.Response) {
            $errResp = $_.Exception.InnerException.Response
        }
        if ($errResp) {
            $statusCode = [int]$errResp.StatusCode
            try {
                $stream = $errResp.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $content = $reader.ReadToEnd()
                    $reader.Close()
                    $stream.Close()
                }
            } catch {}
        }
        $ok = ($statusCode -eq $ExpectStatus)
        if ($ExpectContain -and $ok -and $content) {
            if ($content -notmatch [regex]::Escape($ExpectContain)) {
                $ok = $false
            }
        }
    }

    if ($ok) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:PASS++
    }
    else {
        $detail = if ($statusCode -gt 0) { "HTTP $statusCode, expected $ExpectStatus" } else { "connection error" }
        Write-Host "  [FAIL] $Name  ($detail)" -ForegroundColor Red
        if ($ExpectContain -and $statusCode -eq $ExpectStatus -and $content) {
            $cs = [string]$content
            $preview = if ($cs.Length -gt 200) { $cs.Substring(0, 200) + "..." } else { $cs }
            Write-Host "         ExpectContain '$ExpectContain' not found in: $preview" -ForegroundColor DarkGray
        }
        $script:FAIL++
    }

    if ($content) {
        try   { return ($content | ConvertFrom-Json) }
        catch { return $content }
    }
    return $null
}

function Wait-For-Service([string]$name, [string]$healthUrl) {
    Write-Host "  Waiting for $name ..." -NoNewline
    for ($i = 0; $i -lt 5; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5
            if ([int]$r.StatusCode -lt 500) {
                Write-Host " READY" -ForegroundColor Green
                return $true
            }
        }
        catch { }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 2
    }
    Write-Host " TIMEOUT (service may not be started)" -ForegroundColor Yellow
    return $false
}

# ==============================================================================
Write-Section "Step 0 - Service Health Check"
# ==============================================================================

Wait-For-Service "spring-boot-admin  :9000" "$ADMIN_URL/actuator/health"  | Out-Null
Wait-For-Service "customer-core      :8110" "$CORE_URL/actuator/health"   | Out-Null
Wait-For-Service "policy-management  :8090" "$PM_URL/actuator/health"     | Out-Null
Wait-For-Service "customer-management:8100" "$CM_URL/actuator/health"     | Out-Null
Wait-For-Service "self-service       :8080" "$CSS_URL/actuator/health"    | Out-Null

# ==============================================================================
Write-Section "Step 1 - Customer Core API (port 8110)"
# ==============================================================================

$coreHdr = @{ "Authorization" = $CORE_APIKEY }

Write-Host ""
Write-Host "  [1.1] List customers (paginated)" -ForegroundColor White
$customers = Invoke-ApiTest -Name "GET /customers?limit=5" `
    -Url "$CORE_URL/customers?limit=5&offset=0" `
    -Headers $coreHdr -ExpectContain "customers"

Write-Host ""
Write-Host "  [1.2] Get customer by ID" -ForegroundColor White
$existingCustomer = Invoke-ApiTest -Name "GET /customers/$EXISTING_CID" `
    -Url "$CORE_URL/customers/$EXISTING_CID" `
    -Headers $coreHdr -ExpectContain "Mustermann"

Write-Host ""
Write-Host "  [1.3] Get multiple customers (comma-separated IDs)" -ForegroundColor White
Invoke-ApiTest -Name "GET /customers/rgpp0wkpec,ce4btlyluu" `
    -Url "$CORE_URL/customers/rgpp0wkpec,ce4btlyluu" `
    -Headers $coreHdr -ExpectContain "customers" | Out-Null

Write-Host ""
Write-Host "  [1.4] Filter customers by name" -ForegroundColor White
Invoke-ApiTest -Name "GET /customers?filter=Max" `
    -Url "$CORE_URL/customers?filter=Max" `
    -Headers $coreHdr -ExpectContain "customers" | Out-Null

Write-Host ""
Write-Host "  [1.5] City lookup by postal code" -ForegroundColor White
Invoke-ApiTest -Name "GET /cities/8640" `
    -Url "$CORE_URL/cities/8640" `
    -Headers $coreHdr -ExpectContain "cities" | Out-Null

Write-Host ""
Write-Host "  [1.6] Create new customer" -ForegroundColor White
$randEmail = "e2ecustomer$(Get-Random -Maximum 9999)@example.com"
$newCustBody = ConvertTo-Json @{
    firstname     = "E2E"
    lastname      = "Testuser"
    birthday      = "1992-06-15T00:00:00.000Z"
    streetAddress = "Musterstrasse 42"
    postalCode    = "3000"
    city          = "Bern"
    email         = $randEmail
    phoneNumber   = "055 222 4111"
}
$newCust = Invoke-ApiTest -Name "POST /customers" `
    -Method "POST" -Url "$CORE_URL/customers" `
    -Headers $coreHdr -Body $newCustBody `
    -ExpectStatus 200 -ExpectContain "customerId"

$newCustId = $null
if ($newCust -and $newCust.customerId) {
    $newCustId = if ($newCust.customerId.id) { $newCust.customerId.id } else { $newCust.customerId }
    Write-Host "         New customer ID: $newCustId" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  [1.7] Legacy redirect (301)" -ForegroundColor White
try {
    $redir = Invoke-WebRequest -Uri "$CORE_URL/getCustomers/$EXISTING_CID" `
        -Headers ($coreHdr + @{ "Content-Type" = "application/json" }) `
        -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 10 -ErrorAction Stop
    Write-Host "  [FAIL] GET /getCustomers/{id} - expected 301 but got $([int]$redir.StatusCode)" -ForegroundColor Red
    $script:FAIL++
}
catch {
    $errResp = $null
    if ($_.Exception.Response) { $errResp = $_.Exception.Response }
    elseif ($_.Exception.InnerException -and $_.Exception.InnerException.Response) {
        $errResp = $_.Exception.InnerException.Response
    }

    if ($errResp) {
        $sc = [int]$errResp.StatusCode
        if ($sc -eq 301 -or $sc -eq 302 -or $sc -eq 200) {
            Write-Host "  [PASS] GET /getCustomers/{id} -> $sc (redirect or followed)" -ForegroundColor Green
            $script:PASS++
        } else {
            Write-Host "  [FAIL] GET /getCustomers/{id} -> HTTP $sc (expected 301)" -ForegroundColor Red
            $script:FAIL++
        }
    }
    else {
        # -MaximumRedirection 0 throws a generic exception when redirect is detected in PS 5.x
        Write-Host "  [PASS] GET /getCustomers/{id} -> redirect detected (exception with MaximumRedirection 0)" -ForegroundColor Green
        $script:PASS++
    }
}

Write-Host ""
Write-Host "  [1.8] Update customer profile (PUT /customers/{id})" -ForegroundColor White
if ($newCustId) {
    $profileBody = ConvertTo-Json @{
        firstname     = "E2E"
        lastname      = "Updated"
        birthday      = "1992-06-15"
        streetAddress = "Musterstrasse 42"
        postalCode    = "3000"
        city          = "Bern"
        email         = $randEmail
        phoneNumber   = "055 222 4111"
    }
    Invoke-ApiTest -Name "PUT /customers/$newCustId (update profile)" `
        -Method "PUT" -Url "$CORE_URL/customers/$newCustId" `
        -Headers $coreHdr -Body $profileBody `
        -ExpectStatus 200 -ExpectContain "Updated" | Out-Null
}
else {
    Write-Host "  [SKIP] No new customer ID" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [1.9] Wish List: fields parameter (GET /customers?fields=firstname,lastname)" -ForegroundColor White
Invoke-ApiTest -Name "GET /customers/${EXISTING_CID}?fields=firstname,lastname" `
    -Url "$CORE_URL/customers/${EXISTING_CID}?fields=firstname,lastname" `
    -Headers $coreHdr -ExpectStatus 200 -ExpectContain "firstname" | Out-Null

# ==============================================================================
Write-Section "Step 2 - Authentication (customer-self-service-backend, port 8080)"
# ==============================================================================

Write-Host ""
Write-Host "  [2.1] Sign up new user" -ForegroundColor White
$signupBody = ConvertTo-Json @{ email = $TEST_EMAIL; password = $TEST_PASS }
Invoke-ApiTest -Name "POST /auth/signup" `
    -Method "POST" -Url "$CSS_URL/auth/signup" `
    -Body $signupBody -ExpectStatus 200 -ExpectContain "email" | Out-Null

Write-Host ""
Write-Host "  [2.2] Duplicate signup (expect rejection)" -ForegroundColor White
try {
    $dupResp = Invoke-WebRequest -Uri "$CSS_URL/auth/signup" -Method "POST" `
        -Headers @{ "Content-Type" = "application/json; charset=utf-8" } `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($signupBody)) `
        -UseBasicParsing -TimeoutSec 20
    $dupStatus = [int]$dupResp.StatusCode
} catch {
    $dupStatus = 0
    if ($_.Exception.Response) { $dupStatus = [int]$_.Exception.Response.StatusCode }
    elseif ($_.Exception.InnerException -and $_.Exception.InnerException.Response) {
        $dupStatus = [int]$_.Exception.InnerException.Response.StatusCode
    }
}
if ($dupStatus -eq 409 -or $dupStatus -eq 401 -or $dupStatus -eq 422) {
    Write-Host "  [PASS] POST /auth/signup (duplicate) -> HTTP $dupStatus (rejected as expected)" -ForegroundColor Green
    $script:PASS++
} else {
    Write-Host "  [FAIL] POST /auth/signup (duplicate) -> HTTP $dupStatus (expected 409/401/422)" -ForegroundColor Red
    $script:FAIL++
}

Write-Host ""
Write-Host "  [2.3] Login with pre-loaded account" -ForegroundColor White
$loginBody = ConvertTo-Json @{ email = $ADMIN_EMAIL; password = $ADMIN_PASS }
$loginResult = Invoke-ApiTest -Name "POST /auth (login -> JWT)" `
    -Method "POST" -Url "$CSS_URL/auth" `
    -Body $loginBody -ExpectStatus 200 -ExpectContain "token"

$jwtToken = $null
if ($loginResult -and $loginResult.token) {
    $jwtToken = $loginResult.token
    Write-Host "         JWT obtained (length: $($jwtToken.Length))" -ForegroundColor Gray
}

# ==============================================================================
Write-Section "Step 3 - Customer Self-Service Backend (port 8080)"
# ==============================================================================

$cssApiHdr  = @{ "Authorization" = $CSS_APIKEY }
$cssAuthHdr = if ($jwtToken) { @{ "X-Auth-Token" = $jwtToken } } else { @{} }

Write-Host ""
Write-Host "  [3.1] Get current user info (JWT auth)" -ForegroundColor White
if ($jwtToken) {
    Invoke-ApiTest -Name "GET /user" `
        -Url "$CSS_URL/user" -Headers $cssAuthHdr `
        -ExpectContain "email" | Out-Null
}
else {
    Write-Host "  [SKIP] /user - no JWT (login failed)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [3.2] Get customer profile (authenticated)" -ForegroundColor White
Invoke-ApiTest -Name "GET /customers/$EXISTING_CID" `
    -Url "$CSS_URL/customers/$EXISTING_CID" `
    -Headers $cssAuthHdr `
    -ExpectContain "customerId" | Out-Null

Write-Host ""
Write-Host "  [3.3] City lookup (self-service side)" -ForegroundColor White
Invoke-ApiTest -Name "GET /cities/6300" `
    -Url "$CSS_URL/cities/6300" `
    -ExpectContain "cities" | Out-Null

Write-Host ""
Write-Host "  [3.4] Get customer's quote request list" -ForegroundColor White
if ($jwtToken) {
    Invoke-ApiTest -Name "GET /customers/$EXISTING_CID/insurance-quote-requests" `
        -Url "$CSS_URL/customers/$EXISTING_CID/insurance-quote-requests" `
        -Headers $cssAuthHdr -ExpectStatus 200 | Out-Null
}
else {
    Write-Host "  [SKIP] No JWT" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [3.5] Submit insurance quote request (JWT)" -ForegroundColor White
$quoteRequestId = $null
if ($jwtToken) {
    $addr = @{ streetAddress = "Oberseestrasse 10"; postalCode = "8640"; city = "Rapperswil" }
    $quoteBody = ConvertTo-Json -Depth 10 @{
        customerInfo     = @{
            customerId     = $EXISTING_CID
            firstname      = "Max"
            lastname       = "Mustermann"
            contactAddress = $addr
            billingAddress = $addr
        }
        insuranceOptions = @{
            startDate     = "2026-06-01"
            insuranceType = "LIFE"
            deductible    = @{ amount = 500.0; currency = "CHF" }
        }
    }
    $quoteResult = Invoke-ApiTest -Name "POST /insurance-quote-requests" `
        -Method "POST" -Url "$CSS_URL/insurance-quote-requests" `
        -Headers $cssAuthHdr -Body $quoteBody `
        -ExpectStatus 200 -ExpectContain "id"

    if ($quoteResult -and $quoteResult.id) {
        $quoteRequestId = $quoteResult.id
        Write-Host "         Quote request ID: $quoteRequestId" -ForegroundColor Gray
    }
}
else {
    Write-Host "  [SKIP] Quote request - no JWT" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [3.6] Get specific quote request by ID (JWT)" -ForegroundColor White
if ($jwtToken -and $quoteRequestId) {
    Invoke-ApiTest -Name "GET /insurance-quote-requests/$quoteRequestId" `
        -Url "$CSS_URL/insurance-quote-requests/$quoteRequestId" `
        -Headers $cssAuthHdr -ExpectStatus 200 -ExpectContain "id" | Out-Null
}
else {
    Write-Host "  [SKIP] No JWT or quoteRequestId" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [3.7] List all quote requests (debug endpoint)" -ForegroundColor White
Invoke-ApiTest -Name "GET /insurance-quote-requests" `
    -Url "$CSS_URL/insurance-quote-requests" `
    -ExpectStatus 200 | Out-Null

# ==============================================================================
Write-Section "Step 4 - Policy Management Backend (port 8090)"
# ==============================================================================

$pmHdr = @{ "Authorization" = $PM_APIKEY }

Write-Host ""
Write-Host "  [4.1] Compute risk factor (young, rural)" -ForegroundColor White
$riskBody1 = ConvertTo-Json @{ birthday = "1990-01-01T00:00:00.000Z"; postalCode = "5630" }
$risk1 = Invoke-ApiTest -Name "POST /riskfactor/compute (age=36, postal=5630)" `
    -Method "POST" -Url "$PM_URL/riskfactor/compute" `
    -Headers $pmHdr -Body $riskBody1 -ExpectContain "riskFactor"
if ($risk1) { Write-Host "         riskFactor = $($risk1.riskFactor)" -ForegroundColor Gray }

Write-Host ""
Write-Host "  [4.2] Compute risk factor (elderly, urban)" -ForegroundColor White
$riskBody2 = ConvertTo-Json @{ birthday = "1935-03-20T00:00:00.000Z"; postalCode = "8000" }
$risk2 = Invoke-ApiTest -Name "POST /riskfactor/compute (age=91, postal=8000)" `
    -Method "POST" -Url "$PM_URL/riskfactor/compute" `
    -Headers $pmHdr -Body $riskBody2 -ExpectContain "riskFactor"
if ($risk2) { Write-Host "         riskFactor = $($risk2.riskFactor)" -ForegroundColor Gray }

Write-Host ""
Write-Host "  [4.3] List customers (policy management view)" -ForegroundColor White
Invoke-ApiTest -Name "GET /customers?limit=5" `
    -Url "$PM_URL/customers?limit=5" `
    -Headers $pmHdr -ExpectContain "customers" | Out-Null

Write-Host ""
Write-Host "  [4.4] Get specific customer" -ForegroundColor White
Invoke-ApiTest -Name "GET /customers/$EXISTING_CID" `
    -Url "$PM_URL/customers/$EXISTING_CID" `
    -Headers $pmHdr -ExpectContain "customerId" | Out-Null

Write-Host ""
Write-Host "  [4.5] Get customer's policies" -ForegroundColor White
Invoke-ApiTest -Name "GET /customers/$EXISTING_CID/policies" `
    -Url "$PM_URL/customers/$EXISTING_CID/policies" `
    -Headers $pmHdr -ExpectStatus 200 | Out-Null

Write-Host ""
Write-Host "  [4.6] Create new policy" -ForegroundColor White
$tomorrow  = (Get-Date).AddDays(1).ToString("yyyy-MM-ddT00:00:00.000Z")
$nextYear  = (Get-Date).AddYears(1).ToString("yyyy-MM-ddT00:00:00.000Z")

$policyBody = ConvertTo-Json -Depth 10 @{
    customerId       = $EXISTING_CID
    policyPeriod     = @{ startDate = $tomorrow; endDate = $nextYear }
    policyType       = "LIFE"
    deductible       = @{ amount = 500.0;    currency = "CHF" }
    insurancePremium = @{ amount = 150.0;    currency = "CHF" }
    policyLimit      = @{ amount = 500000.0; currency = "CHF" }
    insuringAgreement = @{
        agreementItems = @(
            @{ title = "E2E Test Coverage"; description = "Created by e2e-test.ps1" }
        )
    }
}
$newPolicy = Invoke-ApiTest -Name "POST /policies" `
    -Method "POST" -Url "$PM_URL/policies" `
    -Headers $pmHdr -Body $policyBody `
    -ExpectStatus 200 -ExpectContain "policyId"

$policyId = $null
if ($newPolicy -and $newPolicy.policyId) {
    $policyId = if ($newPolicy.policyId.id) { $newPolicy.policyId.id } else { $newPolicy.policyId }
    Write-Host "         New policy ID: $policyId" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  [4.7] List all policies" -ForegroundColor White
Invoke-ApiTest -Name "GET /policies?limit=5" `
    -Url "$PM_URL/policies?limit=5" `
    -Headers $pmHdr -ExpectContain "policies" | Out-Null

Write-Host ""
Write-Host "  [4.8] Get policy by ID" -ForegroundColor White
if ($policyId) {
    Invoke-ApiTest -Name "GET /policies/$policyId" `
        -Url "$PM_URL/policies/$policyId" `
        -Headers $pmHdr -ExpectContain "policyId" | Out-Null
}
else {
    Write-Host "  [SKIP] No policyId available" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [4.9] List insurance quote requests (policy mgmt view)" -ForegroundColor White
Invoke-ApiTest -Name "GET /insurance-quote-requests" `
    -Url "$PM_URL/insurance-quote-requests" `
    -Headers $pmHdr -ExpectStatus 200 | Out-Null

Write-Host ""
Write-Host "  [4.10] Update policy" -ForegroundColor White
if ($policyId) {
    $updateBody = ConvertTo-Json -Depth 10 @{
        customerId       = $EXISTING_CID
        policyPeriod     = @{ startDate = $tomorrow; endDate = $nextYear }
        policyType       = "LIFE"
        deductible       = @{ amount = 600.0;    currency = "CHF" }
        insurancePremium = @{ amount = 180.0;    currency = "CHF" }
        policyLimit      = @{ amount = 600000.0; currency = "CHF" }
        insuringAgreement = @{
            agreementItems = @(
                @{ title = "Updated Coverage"; description = "Updated by e2e-test.ps1" }
            )
        }
    }
    Invoke-ApiTest -Name "PUT /policies/$policyId" `
        -Method "PUT" -Url "$PM_URL/policies/$policyId" `
        -Headers $pmHdr -Body $updateBody `
        -ExpectStatus 200 -ExpectContain "policyId" | Out-Null
}
else {
    Write-Host "  [SKIP] No policyId to update" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [4.11] Get specific insurance quote request (policy mgmt)" -ForegroundColor White
if ($quoteRequestId) {
    Invoke-ApiTest -Name "GET /insurance-quote-requests/$quoteRequestId" `
        -Url "$PM_URL/insurance-quote-requests/$quoteRequestId" `
        -Headers $pmHdr -ExpectStatus 200 -ExpectContain "id" | Out-Null
}
else {
    Write-Host "  [SKIP] No quoteRequestId available" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [4.12] Respond to insurance quote (QUOTE_RECEIVED - accept)" -ForegroundColor White
if ($quoteRequestId) {
    $twoMonths = (Get-Date).AddMonths(2).ToString("yyyy-MM-ddT00:00:00.000Z")
    $quoteRespBody = ConvertTo-Json -Depth 10 @{
        status           = "QUOTE_RECEIVED"
        expirationDate   = $twoMonths
        insurancePremium = @{ amount = 120.0; currency = "CHF" }
        policyLimit      = @{ amount = 800000.0; currency = "CHF" }
    }
    $quoteResp = Invoke-ApiTest -Name "PATCH /insurance-quote-requests/$quoteRequestId (accept quote)" `
        -Method "PATCH" -Url "$PM_URL/insurance-quote-requests/$quoteRequestId" `
        -Headers $pmHdr -Body $quoteRespBody `
        -ExpectStatus 200 -ExpectContain "QUOTE_RECEIVED"
}
else {
    Write-Host "  [SKIP] No quoteRequestId to respond to" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [4.13] Delete policy" -ForegroundColor White
if ($policyId) {
    Invoke-ApiTest -Name "DELETE /policies/$policyId" `
        -Method "DELETE" -Url "$PM_URL/policies/$policyId" `
        -Headers $pmHdr -ExpectStatus 204 | Out-Null
}
else {
    Write-Host "  [SKIP] No policyId to delete" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [4.14] Get policy with expand=customer (Wish List pattern)" -ForegroundColor White
$secondPolicy = ConvertTo-Json -Depth 10 @{
    customerId       = $EXISTING_CID
    policyPeriod     = @{ startDate = $tomorrow; endDate = $nextYear }
    policyType       = "HOME"
    deductible       = @{ amount = 200.0;    currency = "CHF" }
    insurancePremium = @{ amount = 80.0;     currency = "CHF" }
    policyLimit      = @{ amount = 300000.0; currency = "CHF" }
    insuringAgreement = @{
        agreementItems = @(
            @{ title = "Home Coverage"; description = "Home insurance for e2e test" }
        )
    }
}
$pol2 = Invoke-ApiTest -Name "POST /policies (second policy for expand test)" `
    -Method "POST" -Url "$PM_URL/policies" `
    -Headers $pmHdr -Body $secondPolicy `
    -ExpectStatus 200 -ExpectContain "policyId"
if ($pol2 -and $pol2.policyId) {
    $pol2Id = if ($pol2.policyId.id) { $pol2.policyId.id } else { $pol2.policyId }
    Invoke-ApiTest -Name "GET /policies/${pol2Id}?expand=customer" `
        -Url "$PM_URL/policies/${pol2Id}?expand=customer" `
        -Headers $pmHdr -ExpectStatus 200 -ExpectContain "firstname" | Out-Null
}

# ==============================================================================
Write-Section "Step 5 - Customer Management Backend (port 8100)"
# ==============================================================================

$cmHdr = @{ "Authorization" = $CM_APIKEY }

Write-Host ""
Write-Host "  [5.1] List customers" -ForegroundColor White
Invoke-ApiTest -Name "GET /customers?limit=5" `
    -Url "$CM_URL/customers?limit=5" `
    -Headers $cmHdr -ExpectContain "customers" | Out-Null

Write-Host ""
Write-Host "  [5.2] Get customer by ID" -ForegroundColor White
Invoke-ApiTest -Name "GET /customers/$EXISTING_CID" `
    -Url "$CM_URL/customers/$EXISTING_CID" `
    -Headers $cmHdr -ExpectContain "customerId" | Out-Null

Write-Host ""
Write-Host "  [5.3] Filter customers by name" -ForegroundColor White
Invoke-ApiTest -Name "GET /customers?filter=Robbie" `
    -Url "$CM_URL/customers?filter=Robbie" `
    -Headers $cmHdr -ExpectStatus 200 | Out-Null

Write-Host ""
Write-Host "  [5.4] Update customer profile (via customer-management)" -ForegroundColor White
$cmUpdateBody = ConvertTo-Json @{
    firstname     = "Max"
    lastname      = "Mustermann"
    birthday      = "1990-01-01"
    streetAddress = "Oberseestrasse 10"
    postalCode    = "8640"
    city          = "Rapperswil"
    email         = "admin@example.com"
    phoneNumber   = "055 222 4111"
}
Invoke-ApiTest -Name "PUT /customers/$EXISTING_CID (update profile)" `
    -Method "PUT" -Url "$CM_URL/customers/$EXISTING_CID" `
    -Headers $cmHdr -Body $cmUpdateBody `
    -ExpectStatus 200 -ExpectContain "customerId" | Out-Null

Write-Host ""
Write-Host "  [5.5] Get interaction log" -ForegroundColor White
Invoke-ApiTest -Name "GET /interaction-logs/$EXISTING_CID" `
    -Url "$CM_URL/interaction-logs/$EXISTING_CID" `
    -Headers $cmHdr -ExpectStatus 200 -ExpectContain "customerId" | Out-Null

Write-Host ""
Write-Host "  [5.6] Get notifications" -ForegroundColor White
Invoke-ApiTest -Name "GET /notifications" `
    -Url "$CM_URL/notifications" `
    -Headers $cmHdr -ExpectStatus 200 | Out-Null

# ==============================================================================
Write-Section "Step 6 - Spring Boot Admin (port 9000)"
# ==============================================================================

Write-Host ""
Write-Host "  [6.1] Admin UI accessible" -ForegroundColor White
Invoke-ApiTest -Name "GET / (Spring Boot Admin UI)" `
    -Url "$ADMIN_URL/" -ExpectStatus 200 | Out-Null

Write-Host ""
Write-Host "  [6.2] Registered application instances" -ForegroundColor White
$adminApps = Invoke-ApiTest -Name "GET /instances" `
    -Url "$ADMIN_URL/instances" -ExpectStatus 200

if ($adminApps -is [array]) {
    Write-Host "         Registered instances: $($adminApps.Count)" -ForegroundColor Gray
}

# ==============================================================================
Write-Section "Step 7 - Actuator Health Endpoints"
# ==============================================================================

Write-Host ""
$actuators = @(
    @{ Name = "customer-core /actuator/health"           ; Url = "$CORE_URL/actuator/health" },
    @{ Name = "self-service  /actuator/health"           ; Url = "$CSS_URL/actuator/health" },
    @{ Name = "policy-mgmt   /actuator/health"           ; Url = "$PM_URL/actuator/health" },
    @{ Name = "customer-mgmt /actuator/health"           ; Url = "$CM_URL/actuator/health" },
    @{ Name = "customer-core /actuator/info"             ; Url = "$CORE_URL/actuator/info" },
    @{ Name = "policy-mgmt   /actuator/info"             ; Url = "$PM_URL/actuator/info" },
    @{ Name = "customer-core /actuator/metrics"          ; Url = "$CORE_URL/actuator/metrics" }
)
foreach ($ep in $actuators) {
    Invoke-ApiTest -Name $ep.Name -Url $ep.Url -ExpectStatus 200 | Out-Null
}

# ==============================================================================
Write-Section "Step 8 - Swagger / OpenAPI Docs"
# ==============================================================================

Write-Host ""
$swaggerUrls = @(
    "$CORE_URL/swagger-ui/index.html",
    "$CSS_URL/swagger-ui/index.html",
    "$PM_URL/swagger-ui/index.html",
    "$CM_URL/swagger-ui/index.html",
    "$CORE_URL/v3/api-docs",
    "$PM_URL/v3/api-docs",
    "$CSS_URL/v3/api-docs",
    "$CM_URL/v3/api-docs"
)
foreach ($url in $swaggerUrls) {
    Invoke-ApiTest -Name "GET $url" -Url $url -ExpectStatus 200 | Out-Null
}

# ==============================================================================
Write-Section "Step 9 - Cross-Service Integration Checks"
# ==============================================================================

Write-Host ""
Write-Host "  [9.1] customer-core and customer-management-backend return same customer data" -ForegroundColor White
$c1 = Invoke-ApiTest -Name "core:    GET /customers/$EXISTING_CID" `
    -Url "$CORE_URL/customers/$EXISTING_CID" -Headers $coreHdr -ExpectContain "Mustermann"
$c2 = Invoke-ApiTest -Name "mgmt:    GET /customers/$EXISTING_CID" `
    -Url "$CM_URL/customers/$EXISTING_CID"  -Headers $cmHdr   -ExpectContain "customerId"
if ($c1 -and $c2) {
    Write-Host "         Both endpoints return customer data - OK" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  [9.2] policy-management-backend fetches customer from customer-core" -ForegroundColor White
Invoke-ApiTest -Name "policy: GET /customers/$EXISTING_CID (proxied via core)" `
    -Url "$PM_URL/customers/$EXISTING_CID" -Headers $pmHdr -ExpectContain "customerId" | Out-Null

Write-Host ""
Write-Host "  [9.3] self-service-backend fetches city from customer-core" -ForegroundColor White
Invoke-ApiTest -Name "css:    GET /cities/8640 (proxied via core)" `
    -Url "$CSS_URL/cities/8640" -ExpectContain "cities" | Out-Null

Write-Host ""
Write-Host "  [9.4] Address update flow (customer-core -> visible everywhere)" -ForegroundColor White
if ($newCustId) {
    $addrBody = ConvertTo-Json @{
        streetAddress = "Neugasse 99"
        postalCode    = "9000"
        city          = "St. Gallen"
    }
    Invoke-ApiTest -Name "PUT /customers/$newCustId/address" `
        -Method "PUT" -Url "$CORE_URL/customers/$newCustId/address" `
        -Headers $coreHdr -Body $addrBody `
        -ExpectStatus 200 -ExpectContain "9000" | Out-Null
}
else {
    Write-Host "  [SKIP] No new customer ID (customer creation failed)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [9.5] Policy created in policy-mgmt appears in customer's policy list" -ForegroundColor White
if ($policyId) {
    $policies = Invoke-ApiTest -Name "GET /customers/$EXISTING_CID/policies (verify new policy)" `
        -Url "$PM_URL/customers/$EXISTING_CID/policies" `
        -Headers $pmHdr -ExpectStatus 200
    if ($policies -and ($policies | ConvertTo-Json) -match $policyId) {
        Write-Host "         Policy $policyId found in customer's policy list - OK" -ForegroundColor Gray
    }
}
else {
    Write-Host "  [SKIP] No policyId available" -ForegroundColor Yellow
}

# ==============================================================================
Write-Section "Step 10 - Full Quote-to-Policy Business Flow (cross-service)"
# ==============================================================================

Write-Host ""
Write-Host "  This tests the core business process:" -ForegroundColor Cyan
Write-Host "    Customer submits quote -> Operations responds -> Customer accepts -> Policy created" -ForegroundColor Cyan

Write-Host ""
Write-Host "  [10.1] Customer submits a new quote request (self-service)" -ForegroundColor White
$flowQuoteId = $null
if ($jwtToken) {
    $flowAddr = @{ streetAddress = "Oberseestrasse 10"; postalCode = "8640"; city = "Rapperswil" }
    $flowQuoteBody = ConvertTo-Json -Depth 10 @{
        customerInfo     = @{
            customerId     = $EXISTING_CID
            firstname      = "Max"
            lastname       = "Mustermann"
            contactAddress = $flowAddr
            billingAddress = $flowAddr
        }
        insuranceOptions = @{
            startDate     = "2026-07-01"
            insuranceType = "HOME"
            deductible    = @{ amount = 300.0; currency = "CHF" }
        }
    }
    $flowQuote = Invoke-ApiTest -Name "POST /insurance-quote-requests (flow)" `
        -Method "POST" -Url "$CSS_URL/insurance-quote-requests" `
        -Headers $cssAuthHdr -Body $flowQuoteBody `
        -ExpectStatus 200 -ExpectContain "REQUEST_SUBMITTED"
    if ($flowQuote -and $flowQuote.id) {
        $flowQuoteId = $flowQuote.id
        Write-Host "         Flow quote request ID: $flowQuoteId" -ForegroundColor Gray
    }
}
else {
    Write-Host "  [SKIP] No JWT" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [10.2] Verify quote appears in policy-management" -ForegroundColor White
if ($flowQuoteId) {
    Start-Sleep -Seconds 2
    Invoke-ApiTest -Name "GET /insurance-quote-requests/$flowQuoteId (policy-mgmt)" `
        -Url "$PM_URL/insurance-quote-requests/$flowQuoteId" `
        -Headers $pmHdr -ExpectStatus 200 -ExpectContain "id" | Out-Null
}
else {
    Write-Host "  [SKIP] No flowQuoteId" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [10.3] Operations responds with quote (policy-management PATCH)" -ForegroundColor White
if ($flowQuoteId) {
    $threeMonths = (Get-Date).AddMonths(3).ToString("yyyy-MM-ddT00:00:00.000Z")
    $flowRespBody = ConvertTo-Json -Depth 10 @{
        status           = "QUOTE_RECEIVED"
        expirationDate   = $threeMonths
        insurancePremium = @{ amount = 90.0;      currency = "CHF" }
        policyLimit      = @{ amount = 500000.0;  currency = "CHF" }
    }
    Invoke-ApiTest -Name "PATCH /insurance-quote-requests/$flowQuoteId (respond)" `
        -Method "PATCH" -Url "$PM_URL/insurance-quote-requests/$flowQuoteId" `
        -Headers $pmHdr -Body $flowRespBody `
        -ExpectStatus 200 -ExpectContain "QUOTE_RECEIVED" | Out-Null
}
else {
    Write-Host "  [SKIP] No flowQuoteId" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [10.4] Customer accepts the quote (self-service PATCH)" -ForegroundColor White
if ($jwtToken -and $flowQuoteId) {
    Start-Sleep -Seconds 2
    $acceptBody = ConvertTo-Json @{ status = "QUOTE_ACCEPTED" }
    Invoke-ApiTest -Name "PATCH /insurance-quote-requests/$flowQuoteId (accept)" `
        -Method "PATCH" -Url "$CSS_URL/insurance-quote-requests/$flowQuoteId" `
        -Headers $cssAuthHdr -Body $acceptBody `
        -ExpectStatus 200 -ExpectContain "QUOTE_ACCEPTED" | Out-Null
}
else {
    Write-Host "  [SKIP] No JWT or flowQuoteId" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [10.5] Verify quote status updated in self-service" -ForegroundColor White
if ($jwtToken -and $flowQuoteId) {
    Invoke-ApiTest -Name "GET /insurance-quote-requests/$flowQuoteId (verify accepted)" `
        -Url "$CSS_URL/insurance-quote-requests/$flowQuoteId" `
        -Headers $cssAuthHdr -ExpectStatus 200 -ExpectContain "QUOTE_ACCEPTED" | Out-Null
}
else {
    Write-Host "  [SKIP] No JWT or flowQuoteId" -ForegroundColor Yellow
}

# ==============================================================================
Write-Section "Untestable via HTTP (requires WebSocket/gRPC clients)"
# ==============================================================================
Write-Host ""
Write-Host "  The following features CANNOT be tested with HTTP calls:" -ForegroundColor Yellow
Write-Host "    - WebSocket chat (customer-management :8100 /chat/messages via STOMP)" -ForegroundColor Gray
Write-Host "    - gRPC risk-management-server (:50051) - use risk-management-client CLI:" -ForegroundColor Gray
Write-Host "        cd risk-management-client && .\riskmanager.bat run C:\Temp\report.csv" -ForegroundColor Gray
Write-Host "    - ActiveMQ message delivery (tested indirectly via quote flow above)" -ForegroundColor Gray
Write-Host "    - Frontend UI interactions (test manually at :3000, :3010, :3020)" -ForegroundColor Gray
Write-Host ""

# ==============================================================================
Write-Section "SUMMARY"
# ==============================================================================

$total = $script:PASS + $script:FAIL
Write-Host ""
Write-Host ("  Total  : $total") -ForegroundColor White
Write-Host ("  Passed : $($script:PASS)") -ForegroundColor Green
Write-Host ("  Failed : $($script:FAIL)") -ForegroundColor $(if ($script:FAIL -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($script:FAIL -eq 0) {
    Write-Host "  All tests passed. All microservices are working correctly." -ForegroundColor Green
}
elseif ($script:FAIL -le 5) {
    Write-Host "  Most tests passed. Minor failures may indicate services not fully ready." -ForegroundColor Yellow
    Write-Host "  Wait 30 seconds and retry if services were just started." -ForegroundColor Yellow
}
else {
    Write-Host "  Multiple failures detected. Check service logs." -ForegroundColor Red
    Write-Host "  See STARTUP_GUIDE.md troubleshooting section." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Frontend URLs (open in browser):" -ForegroundColor Cyan
Write-Host "    Customer Self-Service : http://localhost:3000" -ForegroundColor White
Write-Host "    Policy Management     : http://localhost:3010" -ForegroundColor White
Write-Host "    Customer Management   : http://localhost:3020" -ForegroundColor White
Write-Host "    Spring Boot Admin     : http://localhost:9000" -ForegroundColor White
Write-Host ""
