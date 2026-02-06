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

foreach ($server in $servers) {
    $name = $server.Name
    $rg = $server.ResourceGroupName
    $state = $server.State

    if ($state -eq "Ready") {
        Write-Output "Stopping server '$name' in resource group '$rg' (state: $state)..."
        try {
            Stop-AzPostgreSqlFlexibleServer -Name $name -ResourceGroupName $rg -NoWait
            Write-Output "Stop command sent for '$name'."
        }
        catch {
            Write-Error "Failed to stop '$name': $_"
        }
    }
    else {
        Write-Output "Skipping server '$name' (state: $state)."
    }
}
