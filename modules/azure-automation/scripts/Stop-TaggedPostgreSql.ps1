param(
    [string]$TagKey = "AutoStop",
    [string]$TagValue = "true"
)

# Authenticate using the Automation Account's managed identity
try {
    Connect-AzAccount -Identity | Out-Null
    Write-Output "Authenticated via managed identity."
}
catch {
    Write-Error "Failed to authenticate: $_"
    throw
}

# Find all PostgreSQL Flexible Servers with the target tag
$servers = Get-AzPostgreSqlFlexibleServer | Where-Object {
    $_.Tag[$TagKey] -eq $TagValue
}

if (-not $servers) {
    Write-Output "No PostgreSQL Flexible Servers found with tag ${TagKey}=${TagValue}."
    return
}

$failed = @()

foreach ($server in $servers) {
    $name = $server.Name
    # The server object has no ResourceGroupName property, so take it from the
    # resource ID: /subscriptions/<sub>/resourceGroups/<rg>/providers/...
    $rg = ($server.Id -split '/')[4]
    $state = $server.State

    if ($state -eq "Ready") {
        Write-Output "Stopping server '$name' in resource group '$rg' (state: $state)..."
        try {
            Stop-AzPostgreSqlFlexibleServer -Name $name -ResourceGroupName $rg -NoWait
            Write-Output "Stop command sent for '$name'."
        }
        catch {
            Write-Error "Failed to stop '$name': $_"
            $failed += $name
        }
    }
    else {
        Write-Output "Skipping server '$name' (state: $state)."
    }
}

# Write-Error alone leaves the job "Completed"; throw so a failed stop shows as "Failed"
if ($failed) {
    throw "Failed to stop: $($failed -join ', ')"
}
