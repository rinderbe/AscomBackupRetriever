#Checking dependencies
Write-Host "Checking for Microsoft Secret Store"
if(-not (Get-Module Microsoft.PowerShell.SecretStore -ListAvailable)){
    Install-Module -Name Microsoft.PowerShell.SecretStore -Force
    Write-Log -LogText "Installed Microsoft.PowerShell.SecretStore"
    }
Write-Host "Microsoft Secret store is installed. Proceeding."

#Checking if the Secret Vault is existing for the user
try {
    Get-SecretVault -Name AscomBackupRetriever -ErrorAction STOP
}
catch {
    Write-Host "AscomBackupRetriever vault doesn't exist for this user" -ForegroundColor RED
    Write-Host "Initializing the vault AscomBackupRetriever."
    Register-SecretVault -Name AscomBackupRetriever -ModuleName Microsoft.PowerShell.SecretStore
    Write-Log "Registered the AscomBackupRetriever vault."
}

#Fetching config from JSON
$config = Get-Content -Path .\config.json | ConvertFrom-Json
$ScriptPath = $config.Paths.basepath
$WorkingPath = $config.Paths.libpath
$WebDriverLocation = $WorkingPath+"WebDriver.dll"
$BackupFolder = $config.Paths.backuppath
$LogPath = $config.Paths.logpath
Import-Module $WebDriverLocation

#DEBUG ENABLE. Will disable headless chrome + not quit the chrome window after backup has been finished. 
$DebugEnabled = $config.Settings.EnableDebug

# Add the working directory to the environment path.
# This is required for the ChromeDriver to work.
if (($env:Path -split ';') -notcontains $WorkingPath) {
    $env:Path += ";$WorkingPath"
}

$Global:ChromeOptions = New-Object OpenQA.Selenium.Chrome.ChromeOptions

if ($DebugEnabled -eq $true) {
    $Global:ChromeOptions.AddArguments(@(
    "--disable-extensions",
    "--safebrowsing-disable-download-protection",
    "--safebrowsing-disable-extension-blacklist",
    "--disable-download-protection",
    "--disable-notifications",
    "--ignore-certificate-errors"))
}
else {
    $Global:ChromeOptions.AddArguments(@(
    "--disable-extensions",
    "--safebrowsing-disable-download-protection",
    "--safebrowsing-disable-extension-blacklist",
    "--disable-download-protection",
    "--disable-notifications",
    "--headless",
    "--ignore-certificate-errors"))
}

$Global:ChromeOptions.AddUserProfilePreference("download.default_directory", "$BackupFolder")

if (Test-Path -Path $config.Paths.vaultcred) {
    $q = Unprotect-CmsMessage -Path $config.Paths.vaultcred | ConvertTo-SecureString -AsPlainText -Force
    Unlock-SecretStore -Password $q -PasswordTimeout 28800
}
else {
    Write-Log -LogText "Missing VaultCredentials, exiting script."
    Exit
}
#Loop through the entrys in DeviceList.csv for devices to backup. 

function CheckNodeStatus {
    param (
        [string]$IP
    )
    $DeviceActive = Test-Connection -TargetName "$IP" -Count 1 -Ping
    $DeviceLatency = $DeviceActive.Latency
    
    if ($DeviceActive.Status -eq "Success") {
        Write-Log -LogText "Success: Device $IP is active with $DeviceLatency ms in Latency"
        $NodeAlive = $true
    }
    else {
        Write-Log -LogText "Error: Device $IP is not responding."
        $NodeAlive = $false
    }
    Return $NodeAlive
}

function AscomLogin {
    param (
        [string]$IP,
        [string]$User
    )
    try {
        #Retrieving credentials from Vault. 
        $Secret = Get-Secret -Name "$IP" -Vault AscomBackupRetriever -AsPlainText -ErrorAction STOP
        if (!$Secret) {
            throw "No valid credential found for $IP"
        }
        try {
            #Starting ChromeDriver Object and entering credentials
            $Global:ChromeDriver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($ChromeOptions)
            $Global:ChromeDriver.Navigate().GoToUrl("https://$IP/")
            Start-Sleep -Seconds 1
            $Global:ChromeDriver.FindElement([OpenQA.Selenium.By]::Name(('usr'))).SendKeys("$User")
            $Global:ChromeDriver.FindElement([OpenQA.Selenium.By]::Name(('pwd'))).SendKeys("$Secret")
            $Global:ChromeDriver.FindElement([OpenQA.Selenium.By]::Name(('login'))).Click()
            Start-Sleep -Seconds 1
            try {
                $Global:ChromeDriver.FindElement([OpenQA.Selenium.By]::Name(('cont'))).Click()
                Return $AscomLoginOK = $true
            }
            catch [MethodInvocationException] {
                Write-Log -LogText "Error: Unable to login to device $IP"
                Return $AscomLoginOK = $false
                $Global:ChromeDriver.Quit()
            }
            
        }
        catch {
            Write-Log -LogText "Error: Incompatibility issues, couldn't login on device $IP"
            $AscomLoginOK = $false
            $Global:ChromeDriver.Quit()
        }
    }
    catch {
        Write-Host "No passwords exists for $IP in SecretStore." -ForegroundColor RED
        Write-Log -LogText "No Password exists in vault for device $IP"
        $AscomLoginOK = $false
    }
}

function AscomDeviceURLCheck {
    param (
        [string]$DeviceIPVMID,
        [string]$IP
    )
    try {
        $AscomDeviceCurrentURL = $ChromeDriver.Url
        $AscomDeviceCurrentURLSessionCheck = $AscomDeviceCurrentURL | Select-String -Pattern '/session/' -CaseSensitive
        if ($AscomDeviceCurrentURLSessionCheck) {
            $AscomDeviceBackupURL = "https://$IP/session/cfg.txt?cd=complete-$DeviceIPVMID.txt"
        }
        else {
            $AscomDeviceBackupURL = "https://$IP/cfg.txt?cd=complete-$DeviceIPVMID.txt"
        }
        Return $AscomDeviceBackupURL
    }
    catch {
        Write-Log -LogText "Error: Couldn't get current URL of session for device $IP"
    }
    

}

function AscomGetBackup {
    param (
        [string]$AscomDeviceBackupURL,
        [string]$IPVMID,
        [string]$IP
    )
    try {
        $AscomDeviceBackupURL
        $Global:ChromeDriver.Navigate().GoToUrl("$AscomDeviceBackupURL")
        Start-Sleep -Seconds 1
        $AscomDeviceCurrentBackupFile = "complete-$IPVMID.txt"
        $AscomDeviceCurrentBackupFileFullPath = "$BackupFolder"+$AscomDeviceCurrentBackupFile
        if (Test-Path -Path $AscomDeviceCurrentBackupFileFullPath) {
            Write-Log -LogText "Success: Backup downloaded successfully for $IP"
            $AscomBackupDownloadSuccess = $true
            Return $AscomBackupDownloadSuccess
            $Global:ChromeDriver.Quit()
        }
    }
    catch {
        Write-Log -LogText "Error: Couldn't download backup for device $IP. Possibly old firmware, trying legacy method."
        $AscomBackupDownloadSuccess = $false
        Return $AscomBackupDownloadSuccess
        $Global:ChromeDriver.Quit()
    }
   
}

function AscomGetBackupLegacy {
    param (
        [string]$IP,
        [string]$User,
        [string]$Customer,
        [string]$IPVMID
    )
            #Retrieving credentials from Vault. 
            $AscomDeviceCurrentBackupFile = "complete-$IPVMID.txt"
            $AscomDeviceCurrentBackupFileFullPath = "$BackupFolder"+$AscomDeviceCurrentBackupFile
            $AscomDeviceBackupURL = AscomDeviceURLCheck -DeviceIPVMID "$DeviceIPVMID" -IP "$IP"
            $Secret = Get-Secret -Name "$IP" -Vault AscomBackupRetriever -AsPlainText -ErrorAction STOP
            if (!$Secret) {
                throw "No valid credential found for $IP"
            }
            $SecureStringPass = ConvertTo-SecureString $Secret -AsPlainText -Force
            $Creds = New-Object System.Management.Automation.PSCredential ($User, $SecureStringPass)
            try {
                Invoke-WebRequest -SkipCertificateCheck -Uri $AscomDeviceBackupURL -Credential $Creds -OutFile $AscomDeviceCurrentBackupFileFullPath
                Write-Log -LogText "Success: The legacy method worked, but you still need to upgrade $IP."
                AscomMoveBackupFile -DeviceIPVMID "$DeviceIPVMID" -IP "$IP" -Customer "$Customer"
                #Return $AscomGetBackupLegacySuccess = $true
            }
            catch {
                Write-Host "SHIT FUCKED UP FOR $IP."
                Write-Log -LogText "!ERROR!: Legacy Method failed, no backups will be taken for $IP."
                #Return $AscomGetBackupLegacySuccess = $false
            }
            
}

function AscomMoveBackupFile {
    param (
        [string]$DeviceIPVMID,
        [string]$IP,
        [string]$Customer
    )
    $TodaysDate = (Get-Date).toString("yyyy-MM-dd")
    $CustomerFolder = $BackupFolder+"$TodaysDate"+"\"+$Customer
    $BackupFileName = $BackupFolder+"complete-"+"$DeviceIPVMID"+".txt"
    if (Test-Path -Path $CustomerFolder) {
        try {
            Move-Item -Path $BackupFileName -Destination $CustomerFolder -ErrorAction STOP
            Write-Log -LogText "Success: Backup for $IP was moved to $CustomerFolder"
         }
         catch {
            Write-Log -LogText "Error: Couldn't move file for device $IP"
         }
    } else {
        New-Item -Path "$CustomerFolder" -ItemType Directory
        try {
           Move-Item -Path $BackupFileName -Destination $CustomerFolder -ErrorAction STOP
           Write-Log -LogText "Success: Backup for $IP was moved to $CustomerFolder"
        }
        catch {
            Write-Log -LogText "Error: Couldn't move file for device $IP"
        }
        
    }
}

function Write-Log
{
    Param
    (
        $LogText
    )

    "$(get-date -format "yyyy-MM-dd HH:mm:ss"): $($LogText)" | out-file "$LogPath\log.txt" -Append
}

foreach ($device in (import-csv "$ScriptPath\DeviceList.csv")) {
    $DeviceIPVMID = $device.IPVMID
    $Customer = $device.Customer
    $IP = $device.IP
    $User = $device.User
    if (CheckNodeStatus -IP "$IP") {
        $AscomLoginOK = AscomLogin -IP "$IP" -User "$User"
        if ($AscomLoginOK -eq $true) {
            $AscomDeviceBackupURL = AscomDeviceURLCheck -DeviceIPVMID "$DeviceIPVMID" -IP "$IP"
            $AscomBackupDownloadSuccess = AscomGetBackup -AscomDeviceBackupURL "$AscomDeviceBackupURL" -IPVMID "$DeviceIPVMID" -IP "$IP"
            if ($AscomBackupDownloadSuccess -eq $true) {
                AscomMoveBackupFile -DeviceIPVMID "$DeviceIPVMID" -IP "$IP" -Customer "$Customer"
            }
            else {
                AscomGetBackupLegacy -IP "$IP" -User "$User" -IPVMID "$DeviceIPVMID" -Customer "$Customer"
            }
        }
        else {
            AscomGetBackupLegacy -IP "$IP" -User "$User" -IPVMID "$DeviceIPVMID" -Customer "$Customer"
        }

    }
    else {

    }
}