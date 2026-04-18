##############################################################################
# Lakeside Mutual Monolith - End-to-End API Test Script
# Covers ALL REST endpoints exposed by the monolith application
##############################################################################

$BASE = "http://localhost:8080"
$pass = 0
$fail = 0
$total = 0

function Test-Endpoint {
    param(
        [string]$Method,
        [string]$Url,
        [string]$Description,
        [string]$Body = $null,
        [hashtable]$Headers = @{ "Accept" = "application/json" },
        [int[]]$ExpectedStatus = @(200)
    )
    $script:total++
    try {
        $params = @{
            Method  = $Method
            Uri     = $Url
            Headers = $Headers
        }
        if ($Body) {
            $params["Body"] = $Body
            if (-not $Headers.ContainsKey("Content-Type")) {
                $Headers["Content-Type"] = "application/json"
            }
        }

        $response = Invoke-WebRequest @params -UseBasicParsing -ErrorAction Stop
        $status = $response.StatusCode
        if ($ExpectedStatus -contains $status) {
            Write-Host "[PASS] $Description  (HTTP $status)" -ForegroundColor Green
            $script:pass++
            return $response
        } else {
            Write-Host "[FAIL] $Description  (Expected $($ExpectedStatus -join '/'), got $status)" -ForegroundColor Red
            $script:fail++
            return $null
        }
    }
    catch {
        $statusCode = 0
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($ExpectedStatus -contains $statusCode) {
            Write-Host "[PASS] $Description  (HTTP $statusCode as expected)" -ForegroundColor Green
            $script:pass++
            return $null
        }
        Write-Host "[FAIL] $Description  (Error: $($_.Exception.Message))" -ForegroundColor Red
        $script:fail++
        return $null
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Lakeside Mutual Monolith - API Test Suite" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------------
# 0. Health check
# ------------------------------------------------------------------
Write-Host "--- [Section 0] Health & Infrastructure ---" -ForegroundColor Yellow

Test-Endpoint -Method GET -Url "$BASE/actuator/health" `
    -Description "Actuator health endpoint"

Test-Endpoint -Method GET -Url "$BASE/actuator" `
    -Description "Actuator root endpoint"

Test-Endpoint -Method GET -Url "$BASE/v3/api-docs" `
    -Description "OpenAPI docs (JSON)"

Test-Endpoint -Method GET -Url "$BASE/swagger-ui/index.html" `
    -Description "Swagger UI page" `
    -Headers @{ "Accept" = "text/html" }

# ------------------------------------------------------------------
# 1. Self-Service Authentication (public)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 1] Self-Service Auth ---" -ForegroundColor Yellow

$loginBody = '{"email":"admin@example.com","password":"1password"}'
$loginResp = Test-Endpoint -Method POST -Url "$BASE/api/selfservice/auth" `
    -Description "Login with seed user (admin@example.com)" `
    -Body $loginBody `
    -Headers @{ "Accept" = "application/json"; "Content-Type" = "application/json" }

$TOKEN = ""
if ($loginResp) {
    $json = $loginResp.Content | ConvertFrom-Json
    $TOKEN = $json.token
    Write-Host "  -> JWT Token obtained: $($TOKEN.Substring(0, [Math]::Min(30, $TOKEN.Length)))..." -ForegroundColor DarkGray
}

$signupBody = '{"email":"testuser_' + (Get-Random) + '@test.com","password":"Test1234"}'
Test-Endpoint -Method POST -Url "$BASE/api/selfservice/auth/signup" `
    -Description "Sign up new user" `
    -Body $signupBody `
    -Headers @{ "Accept" = "application/json"; "Content-Type" = "application/json" }

$dupSignupBody = '{"email":"admin@example.com","password":"1password"}'
Test-Endpoint -Method POST -Url "$BASE/api/selfservice/auth/signup" `
    -Description "Sign up duplicate user (expect 409)" `
    -Body $dupSignupBody `
    -Headers @{ "Accept" = "application/json"; "Content-Type" = "application/json" } `
    -ExpectedStatus @(409, 500)

# ------------------------------------------------------------------
# 2. Self-Service User (authenticated)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 2] Self-Service User ---" -ForegroundColor Yellow

$authHeaders = @{
    "Accept"       = "application/json"
    "X-Auth-Token" = $TOKEN
}

Test-Endpoint -Method GET -Url "$BASE/api/selfservice/user" `
    -Description "Get current user (authenticated)" `
    -Headers $authHeaders

# ------------------------------------------------------------------
# 3. Self-Service Customer (authenticated)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 3] Self-Service Customer ---" -ForegroundColor Yellow

$CUSTOMER_ID = "rgpp0wkpec"

Test-Endpoint -Method GET -Url "$BASE/api/selfservice/customers/$CUSTOMER_ID" `
    -Description "Get customer by ID (self-service)" `
    -Headers $authHeaders

$addressBody = '{"streetAddress":"Bahnhofstrasse 1","postalCode":"8001","city":"Zurich"}'
$authHeadersWithCT = @{
    "Accept"       = "application/json"
    "Content-Type" = "application/json"
    "X-Auth-Token" = $TOKEN
}
Test-Endpoint -Method PUT -Url "$BASE/api/selfservice/customers/$CUSTOMER_ID/address" `
    -Description "Change customer address" `
    -Body $addressBody `
    -Headers $authHeadersWithCT

Test-Endpoint -Method GET -Url "$BASE/api/selfservice/customers/$CUSTOMER_ID/insurance-quote-requests" `
    -Description "Get customer's insurance quote requests" `
    -Headers $authHeaders

# ------------------------------------------------------------------
# 4. Self-Service Cities (authenticated)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 4] Self-Service Cities ---" -ForegroundColor Yellow

Test-Endpoint -Method GET -Url "$BASE/api/selfservice/cities/8640" `
    -Description "Lookup cities for postal code 8640" `
    -Headers $authHeaders

Test-Endpoint -Method GET -Url "$BASE/api/selfservice/cities/8001" `
    -Description "Lookup cities for postal code 8001" `
    -Headers $authHeaders

# ------------------------------------------------------------------
# 5. Self-Service Insurance Quote Request (authenticated)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 5] Self-Service Insurance Quote Requests ---" -ForegroundColor Yellow

Test-Endpoint -Method GET -Url "$BASE/api/selfservice/insurance-quote-requests" `
    -Description "List all insurance quote requests (debug)" `
    -Headers $authHeaders

$quoteRequestBody = @{
    customerInfo    = @{
        customerId     = $CUSTOMER_ID
        firstname      = "Max"
        lastname       = "Mustermann"
        contactAddress = @{ streetAddress = "Oberseestrasse 10"; postalCode = "8640"; city = "Rapperswil" }
        billingAddress = @{ streetAddress = "Oberseestrasse 10"; postalCode = "8640"; city = "Rapperswil" }
    }
    insuranceOptions = @{
        startDate     = "2026-06-01"
        insuranceType = "Life Insurance"
        deductible    = @{ amount = 1000; currency = "CHF" }
    }
} | ConvertTo-Json -Depth 5

$quoteResp = Test-Endpoint -Method POST -Url "$BASE/api/selfservice/insurance-quote-requests" `
    -Description "Create new insurance quote request" `
    -Body $quoteRequestBody `
    -Headers $authHeadersWithCT

$QUOTE_REQUEST_ID = $null
if ($quoteResp) {
    $qrJson = $quoteResp.Content | ConvertFrom-Json
    $QUOTE_REQUEST_ID = $qrJson.id
    Write-Host "  -> Created quote request ID: $QUOTE_REQUEST_ID" -ForegroundColor DarkGray
}

if ($QUOTE_REQUEST_ID) {
    Test-Endpoint -Method GET -Url "$BASE/api/selfservice/insurance-quote-requests/$QUOTE_REQUEST_ID" `
        -Description "Get specific insurance quote request" `
        -Headers $authHeaders
}

# ------------------------------------------------------------------
# 6. Management Customers (no auth)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 6] Management Customers ---" -ForegroundColor Yellow

Test-Endpoint -Method GET -Url "$BASE/api/management/customers?limit=5&offset=0" `
    -Description "List customers (management)" 

Test-Endpoint -Method GET -Url "$BASE/api/management/customers?filter=Max&limit=5&offset=0" `
    -Description "Search customers by name 'Max'" 

Test-Endpoint -Method GET -Url "$BASE/api/management/customers/$CUSTOMER_ID" `
    -Description "Get customer by ID (management)" 

$updateCustomerBody = @{
    firstname   = "Max"
    lastname    = "Mustermann"
    birthday    = "1990-01-01T00:00:00.000+00:00"
    streetAddress = "Oberseestrasse 10"
    postalCode  = "8640"
    city        = "Rapperswil"
    email       = "admin@example.com"
    phoneNumber = "055 222 4111"
} | ConvertTo-Json
Test-Endpoint -Method PUT -Url "$BASE/api/management/customers/$CUSTOMER_ID" `
    -Description "Update customer profile (management)" `
    -Body $updateCustomerBody `
    -Headers @{ "Accept" = "application/json"; "Content-Type" = "application/json" }

# ------------------------------------------------------------------
# 7. Interaction Logs (no auth)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 7] Interaction Logs ---" -ForegroundColor Yellow

Test-Endpoint -Method GET -Url "$BASE/api/management/interaction-logs/$CUSTOMER_ID" `
    -Description "Get interaction log for customer"

$interactionBody = '{"lastAcknowledgedInteractionId":"dummy-interaction-id"}'
Test-Endpoint -Method PATCH -Url "$BASE/api/management/interaction-logs/$CUSTOMER_ID" `
    -Description "Acknowledge interactions (PATCH interaction log)" `
    -Body $interactionBody `
    -Headers @{ "Accept" = "application/json"; "Content-Type" = "application/json" } `
    -ExpectedStatus @(200, 404)

# ------------------------------------------------------------------
# 8. Notifications (no auth)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 8] Notifications ---" -ForegroundColor Yellow

Test-Endpoint -Method GET -Url "$BASE/api/management/notifications" `
    -Description "Get notifications"

# ------------------------------------------------------------------
# 9. Policy Customers (no auth)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 9] Policy Customers ---" -ForegroundColor Yellow

Test-Endpoint -Method GET -Url "$BASE/api/policy/customers?limit=5&offset=0" `
    -Description "List customers (policy)" 

Test-Endpoint -Method GET -Url "$BASE/api/policy/customers?filter=Max&limit=5&offset=0" `
    -Description "Search policy customers by 'Max'" 

Test-Endpoint -Method GET -Url "$BASE/api/policy/customers/$CUSTOMER_ID" `
    -Description "Get policy customer by ID"

Test-Endpoint -Method GET -Url "$BASE/api/policy/customers/${CUSTOMER_ID}/policies" `
    -Description "Get customer's policies"

# ------------------------------------------------------------------
# 10. Policies (no auth)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 10] Policies ---" -ForegroundColor Yellow

Test-Endpoint -Method GET -Url "$BASE/api/policy/policies?limit=5&offset=0" `
    -Description "List all policies"

$POLICY_ID = "fvo5pkqerr"
Test-Endpoint -Method GET -Url "$BASE/api/policy/policies/${POLICY_ID}?expand=customer" `
    -Description "Get specific policy with customer expand"

$newPolicyBody = @{
    customerId       = $CUSTOMER_ID
    policyPeriod     = @{ startDate = "2026-05-01"; endDate = "2027-05-01" }
    policyType       = "Health Insurance"
    policyLimit      = @{ amount = 500000; currency = "CHF" }
    deductible       = @{ amount = 2000; currency = "CHF" }
    insurancePremium = @{ amount = 300; currency = "CHF" }
    insuringAgreement = @{ agreementItems = @(
        @{ title = "Hospitalization"; description = "Covers hospital stays"; value = 1 }
    )}
} | ConvertTo-Json -Depth 4

$policyResp = Test-Endpoint -Method POST -Url "$BASE/api/policy/policies" `
    -Description "Create new policy" `
    -Body $newPolicyBody `
    -Headers @{ "Accept" = "application/json"; "Content-Type" = "application/json" }

$NEW_POLICY_ID = $null
if ($policyResp) {
    $pJson = $policyResp.Content | ConvertFrom-Json
    $NEW_POLICY_ID = $pJson.policyId
    Write-Host "  -> Created policy ID: $NEW_POLICY_ID" -ForegroundColor DarkGray
}

if ($NEW_POLICY_ID) {
    $updatePolicyBody = @{
        customerId       = $CUSTOMER_ID
        policyPeriod     = @{ startDate = "2026-05-01"; endDate = "2028-05-01" }
        policyType       = "Health Insurance"
        policyLimit      = @{ amount = 600000; currency = "CHF" }
        deductible       = @{ amount = 2500; currency = "CHF" }
        insurancePremium = @{ amount = 350; currency = "CHF" }
        insuringAgreement = @{ agreementItems = @(
            @{ title = "Hospitalization"; description = "Covers hospital stays extended"; value = 1 }
        )}
    } | ConvertTo-Json -Depth 4

    Test-Endpoint -Method PUT -Url "$BASE/api/policy/policies/$NEW_POLICY_ID" `
        -Description "Update the new policy" `
        -Body $updatePolicyBody `
        -Headers @{ "Accept" = "application/json"; "Content-Type" = "application/json" }

    Test-Endpoint -Method DELETE -Url "$BASE/api/policy/policies/$NEW_POLICY_ID" `
        -Description "Delete the new policy" `
        -Headers @{ "Accept" = "application/json" } `
        -ExpectedStatus @(200, 204)
}

# ------------------------------------------------------------------
# 11. Policy Insurance Quote Requests (no auth)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 11] Policy Insurance Quote Requests ---" -ForegroundColor Yellow

Test-Endpoint -Method GET -Url "$BASE/api/policy/insurance-quote-requests" `
    -Description "List policy insurance quote requests"

if ($QUOTE_REQUEST_ID) {
    Test-Endpoint -Method GET -Url "$BASE/api/policy/insurance-quote-requests/$QUOTE_REQUEST_ID" `
        -Description "Get specific policy insurance quote request"

    $respondBody = @{
        status          = "QUOTE_RECEIVED"
        expirationDate  = "2026-12-31T23:59:59.000+00:00"
        insurancePremium = @{ amount = 300; currency = "CHF" }
        policyLimit      = @{ amount = 500000; currency = "CHF" }
    } | ConvertTo-Json -Depth 3

    Test-Endpoint -Method PATCH -Url "$BASE/api/policy/insurance-quote-requests/$QUOTE_REQUEST_ID" `
        -Description "Respond to insurance quote request (accept)" `
        -Body $respondBody `
        -Headers @{ "Accept" = "application/json"; "Content-Type" = "application/json" }
}

# ------------------------------------------------------------------
# 12. Self-Service: Respond to quote (customer accepts)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 12] Self-Service: Customer Quote Response ---" -ForegroundColor Yellow

if ($QUOTE_REQUEST_ID -and $TOKEN) {
    $acceptBody = '{"status":"QUOTE_ACCEPTED"}'
    Test-Endpoint -Method PATCH -Url "$BASE/api/selfservice/insurance-quote-requests/$QUOTE_REQUEST_ID" `
        -Description "Customer accepts the insurance quote" `
        -Body $acceptBody `
        -Headers $authHeadersWithCT
}

# ------------------------------------------------------------------
# 13. Risk Factor Computation (no auth)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 13] Risk Factor Computation ---" -ForegroundColor Yellow

$riskBody = '{"birthday":"1990-01-01T00:00:00.000+00:00","postalCode":"8640"}'
Test-Endpoint -Method POST -Url "$BASE/api/policy/riskfactor/compute" `
    -Description "Compute risk factor" `
    -Body $riskBody `
    -Headers @{ "Accept" = "application/json"; "Content-Type" = "application/json" }

$riskBody2 = '{"birthday":"1950-06-15T00:00:00.000+00:00","postalCode":"1000"}'
Test-Endpoint -Method POST -Url "$BASE/api/policy/riskfactor/compute" `
    -Description "Compute risk factor (elderly, high-risk zone)" `
    -Body $riskBody2 `
    -Headers @{ "Accept" = "application/json"; "Content-Type" = "application/json" }

# ------------------------------------------------------------------
# 14. H2 Console availability
# ------------------------------------------------------------------
Write-Host ""
Write-Host "--- [Section 14] H2 Console ---" -ForegroundColor Yellow

Test-Endpoint -Method GET -Url "$BASE/h2-console" `
    -Description "H2 Console page" `
    -Headers @{ "Accept" = "text/html" } `
    -ExpectedStatus @(200, 302)

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Test Summary: $pass PASSED / $fail FAILED / $total TOTAL" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
