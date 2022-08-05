$config = Get-Content -Path .\config.json | ConvertFrom-Json

$DeviceList = $config.Paths.devicelist

foreach ($device in (import-csv $DeviceList)) {
    $IP = $device.IP

    try {
        $s = Get-Secret -Name "$IP" -Vault AscomBackupRetriever -AsPlainText -ErrorAction STOP
        "Password found for $IP"
    }
    catch {
        "Secret is missing for $IP - creating new secret for device. "
        $q = Read-Host "Enter password for $IP"
        Set-Secret -Name "$IP" -Secret "$q"
    }
        
    }
