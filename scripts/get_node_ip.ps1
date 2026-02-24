param (
    [string]$NodeName,
    [string]$SwitchName
)

# Wait for the VM to get an IPv4 address (larger VMs take longer to boot)
$maxRetries = 30
$retryInterval = 10
$ip = $null

for ($i = 0; $i -lt $maxRetries; $i++) {
    $ip = (Get-VMNetworkAdapter -VMName $NodeName).IPAddresses | Where-Object { $_ -match '^(\d{1,3}\.){3}\d{1,3}$' } | Select-Object -First 1
    if ($ip) { break }
    Start-Sleep -Seconds $retryInterval
}

if (-not $ip) {
    Write-Error "Timed out waiting for IP address on VM $NodeName"
    exit 1
}

$prefix_length = (Get-NetIPAddress -InterfaceAlias "vEthernet ($SwitchName)" | Where-Object {$_.AddressFamily -eq "IPv4"}).PrefixLength | Select-Object -First 1
$gateway = (Get-NetIPConfiguration -InterfaceAlias "vEthernet ($SwitchName)").IPv4DefaultGateway.NextHop | Select-Object -First 1

@{ ip = "$ip"; prefix_length = "$prefix_length"; gateway = "$gateway" } | ConvertTo-Json -Compress
