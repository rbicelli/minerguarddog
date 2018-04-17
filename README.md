# minerguarddog
Miner watchdog for Windows, compatible with [xmr-stak](https://github.com/fireice-uk/xmr-stak) and [cast-xmr](http://www.gandalph3000.com/)

Mining with RX Vegas in Windows could be a PITA. You have always to check if everything is running fine and sometimes cross fingers.

This watchdog comes in help:
* Checks if miner process is running and responding, otherwise the watchdog restars it
* Checks if video cards are present (sometimes a Vega "disappears" from system), otherwise the watchdog reboots System
* Checks for hashrate drops, otherwise the watchdog restars the miner

Before starting miner the watchdog disables then re-enables video cards and applies overdriventool profiles.

## Installation
* Place files minerguarddog.vbs and minergguarddog.example.ini in your miners directory.
* It is recommended that you put your miner in a subdirectory where the script is contained.
* Place [overdriventool.exe](https://forums.guru3d.com/threads/overdriventool-tool-for-amd-gpus.416116/) and [devcon.exe](https://docs.microsoft.com/en-us/windows-hardware/drivers/devtest/devcon) in the script directory.
* Rename minergguarddog.example.ini in minerguarddog.ini
* Edit minerguarddog.ini to suit your needs, configuration is well commented so it's easy
* Run minerguarddog.vbs as Admin or schedule at user logon with task scheduler, making sure the process will be started as admin

## Planned Features
* CPU temperature monitor (using OpenHardwareMonitor)
