Ascom Backup Retriever
============

Simple script to automate backups for Ascom IP-Dect.

The script is tested with the following versions:

* 5.1.8 (NOT working due to the old TLS-version implemented - anyhow you should consider upgrading if you still have this in your environment.)
* 7.2.13
* 11.4.4
* 11.7.2

On the following platforms:

* IPBL
* IPBS1
* IPBS2
* IPBS3
* IPVM

Prerequisits
------------

* ChromeDriver
  * Tested with version 104.0.5112.79
* Webdriver.dll
  * Tested with version 4.3.0
* Powershell
  * Tested with version 7.2.5
* Microsoft PowerShell SecretStore



Installation
------------

* Download the latest ChromeDriver from <https://chromedriver.chromium.org/downloads>
* Download the latest Webdriver for C# from <https://www.nuget.org/api/v2/package/Selenium.WebDriver>
* Git clone this repository

### Setup of Ascom Backup Retriever ###

Start with setting up the directory configuration in the file config.json - search and replace to suit your installation path. And yes, quite lame config and lazy not to use a more dynamic structure. :-)<br>

~~~json
#config.json
{
    "Paths": {
      "basepath": "X:\\AscomBackupRetriever\\",
      "backuppath": "X:\\AscomBackupRetriever\\Backups\\",
      "libpath": "X:\\AscomBackupRetriever\\lib\\",
      "infpath": "X:\\AscomBackupRetriever\\lib\\DocumentEncryption.inf",
      "cerpath": "X:\\AscomBackupRetriever\\lib\\DocumentEncryption.cer",
      "vaultcred": "X:\\AscomBackupRetriever\\lib\\vaultCred.key",
      "devicelist": "X:\\AscomBackupRetriever\\DeviceList.csv",
      "logpath": "X:\\AscomBackupRetriever\\Logs\\"
    },
    "Settings": {
        "EnableDebug": "$false"
    }
  }
~~~

### Chromedriver ###

Unpack the ZIP-file and put the 'chromedriver.exe' in the 'lib'-directory.

### WebDriver ###

Unpack the 'nupkg'-file with 7zip or some other competent decompresser of your choice. The file WebDriver.dll can be found in the 'selenium.webdriver.4.3.0\lib\net5.0' (if you downloaded version 4.3.0). Copy this file to the 'lib'-directory in the AscomBackupRetriever directory.

### Create key + certificate for "safe" storage of VaultCredentials ###

1. Start a PowerShell terminal.
2. Execute CreateCert.ps1.
3. Enter the CN that you'd like to use for your certificate and key.
4. Enter the Vault Password that you will use in a later stage to store Ascom credentials in.
5. Verify that you now have an INF, CER and the vaultCred.key-file in the 'lib'-directory.

### Enter the devices you'd like to backup ###

Open up the file 'devicelist.csv' in either your favorite text editor or in Excel. <br> Put in the devices you'd like to backup.

'devicelist.csv'

~~~csv
User,IP,IPVMID,Customer
backupuser,XX.YY.XX.YY,IPVM-a1-ab-86,CUSTOMER_A
~~~

* User = Username of the user that can login to the device.
* IP = IP-Adress where you can reach your Ascom-device.
* IPVMID = Sorry for the naming convention. But this ID consists of the device type + part of the device MAC-address. If you're unsure where to find this, it can either be found in the backup itself, or in the name of the actual backup file.
* Customer = A descriptive name of either the customer the device is used for or the name of the system. Is only used now to create a directory structure and nothing else.

### Fill the Microsoft Secret Vault with Ascom-credentials ###

1. Make sure that you've configured devices in 'devicelist.csv'.
2. Start a PowerShell terminal.
3. Execute CredentialsFiller.ps1 - this will loop through all IP's in devicelist and search for a matching entry in the Vault. If none is found, you'll be prompted to enter the secret for the device.

Execution
------------

Now you're ready to kick off the actual backup.

1. Start a PowerShell terminal.
2. Execute BackupFetcher.ps1.
3. Sit back and relax.
4. Have a look at the logs in the 'Logs'-directory to verify if there are any Errors.

Successful log entry for a device with firmware 11.4 -> 11.7.

~~~log
 2022-08-04 21:41:08: Success: Device 10.10.1.116 is active with 0 ms in Latency
 2022-08-04 21:41:12: Success: Backup downloaded successfully for 10.10.1.116
 2022-08-04 21:41:12: Success: Backup for 10.10.1.116 was moved to D:\RIND\AscomBackupRetriever\Backups\2022-08-04\SINV
~~~

Successful log entry for an older device where BasicAuth is used.

~~~log
 2022-08-04 21:41:22: Success: Device 10.132.1.21 is active with 0 ms in Latency
 2022-08-04 21:41:23: Error: Incompatibility issues, couldn't login on device 10.132.1.21
 2022-08-04 21:41:24: Success: The legacy method worked, but you still need to upgrade 10.132.1.21.
 2022-08-04 21:41:24: Success: Backup for 10.132.1.21 was moved to D:\RIND\AscomBackupRetriever\Backups\2022-08-04\AKADEM
~~~

Failed backup log entry

~~~log
 2022-08-04 21:41:27: Success: Device 172.16.195.10 is active with 1 ms in Latency
 2022-08-04 21:41:28: Error: Incompatibility issues, couldn't login on device 172.16.195.10
 2022-08-04 21:41:29: !ERROR!: Legacy Method failed, no backups will be taken for 172.16.195.10.
~~~

Scheduling
------------

Important is that you run the scheduled task with the same user that created the vault and the keys to unlock the vault. <br>
Create a scheduled task with the settings you find reasonable for your case. Execute Powershell, in my case this is "C:\Program Files\PowerShell\7\pwsh.exe". And the following parameters "-WorkingDirectory X:\AscomBackupRetriever -F X:\AscomBackupRetriever\BackupFetcher.ps1".

Troubleshooting
------------

Here comes some tips regarding troubleshooting for the script.

1. Enable debugging in your 'config.json'-file. This disables headless-mode on the chromedriver and gives you a browser GUI where you can see what happens.

2. You might have to comment out 'ChromeDriver.Quit()' from the BackupFetcher.ps1-script, otherwise the browser GUI will close itself. Disabling this when enabling debug-mode will be implemented.
