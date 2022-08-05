<#
Script to create cert + private key + encrypting the Vault Credentials into lib\vaultCred.key.
This file will be used when scheduling the backups to "securely" fetching the credentials for the vault. 
#>

$CN = Read-Host "Enter the CN that you wish to use with your cert "CN=a@b.c""
$VaultSecret = Read-Host "Enter the Vault Password" -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($VaultSecret)
$UnsafeVaultSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)

$config = Get-Content -Path .\config.json | ConvertFrom-Json

$InfPath = $config.Paths.infpath
$CerPath = $config.Paths.cerpath
$VaultCred = $config.Paths.vaultcred

if (Test-Path -Path $InfPath) {
    "INF-File already exists."
}
else {
    "Creating INF-File. "
    # Create .INF file for certreq
    {[Version]
        Signature = "$Windows NT$"
        
        [Strings]
        szOID_ENHANCED_KEY_USAGE = "2.5.29.37"
        szOID_DOCUMENT_ENCRYPTION = "1.3.6.1.4.1.311.80.1"
        
        [NewRequest]
        Subject = "$CN"
        MachineKeySet = false
        KeyLength = 2048
        KeySpec = AT_KEYEXCHANGE
        HashAlgorithm = Sha1
        Exportable = true
        RequestType = Cert
        KeyUsage = "CERT_KEY_ENCIPHERMENT_KEY_USAGE | CERT_DATA_ENCIPHERMENT_KEY_USAGE"
        ValidityPeriod = "Years"
        ValidityPeriodUnits = "1000"
        
        [Extensions]
        %szOID_ENHANCED_KEY_USAGE% = "{text}%szOID_DOCUMENT_ENCRYPTION%"
        } | Out-File -FilePath $InfPath
}


if (Test-Path -Path $CerPath) {
    "CER-File already exists."
}
else {
    certreq.exe -new $InfPath $CerPath
}

if (Test-Path -Path $VaultCred) {
    "VaultCred already exists."
}
else {
    Protect-CmsMessage -Content "$UnsafeVaultSecret" -To "$CN" -OutFile $VaultCred
}
