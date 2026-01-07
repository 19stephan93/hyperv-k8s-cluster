param (
    [string]$NodeName,
    [string]$SwitchName
)

$ip = (Get-VMNetworkAdapter -VMName $NodeName).IPAddresses | Where-Object { $_ -match '^(\d{1,3}\.){3}\d{1,3}$' }
$prefix_length = (Get-NetIPAddress -InterfaceAlias "vEthernet ($SwitchName)" | Where-Object {$_.AddressFamily -eq "IPv4"}).PrefixLength
$gateway = (Get-NetIPConfiguration -InterfaceAlias "vEthernet ($SwitchName)").IPv4DefaultGateway.NextHop
@{ ip = $ip; prefix_length = "$prefix_length";; gateway = $gateway} | ConvertTo-Json -Compress