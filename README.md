# MinerGuardDog
Miner watchdog for Windows, compatible with 
* [xmr-stak](https://github.com/fireice-uk/xmr-stak)
* [cast-xmr](http://www.gandalph3000.com/)
* [srb-miner](https://bitcointalk.org/index.php?topic=3167363.0)

Mining with AMD GPUs in Windows could be a PITA. You have always to check if everything is running fine and sometimes cross fingers.

This watchdog comes in help:
* Checks if miner process is running and responding, otherwise the watchdog restarts it
* Checks if video cards are present (sometimes a Vega "disappears" from system), otherwise the watchdog reboots System
* Checks for hashrate drops, otherwise the watchdog restars the miner
* Checks temperatures of your cards, in case temperature raises above limit you set it pauses miner, reboot or shutdown system according to settings
* Auto detect cards, run devcon disable/enable, and applies Overdriventool profiles. You can schedule to apply profiles after miner is started. See example INI file for better explaination
* Auto disable Crossfire and Ulps in Registry
* Round-Robin rig sharing in xmr-stak (see Example INI file)
* Send Telegram Notifications

## Installation
* Place files minerguarddog.vbs and minergguarddog.example.ini in your miners directory.
* Place your miner(s) in a subdirectory where the script is contained.
* Place [overdriventool.exe](https://forums.guru3d.com/threads/overdriventool-tool-for-amd-gpus.416116/) and [devcon.exe](https://docs.microsoft.com/en-us/windows-hardware/drivers/devtest/devcon) in the script directory.
* For temperature monitoring place [openhardwaremonitor](http://www.openhardwaremonitor.org) in scriptdir/openhardwaremonitor
* Run Openhardwaremonitor and Configure HTTP Monitoring: Set port in Options->Remote Web Server->Port, and run web server Options->Remote Web Server->Run. Close Openhardwaremonitor in order to save configuration.
* Rename minergguarddog.example.ini in minerguarddog.ini
* Edit minerguarddog.ini to suit your needs, configuration is well commented so it's easy
* Run minerguarddog.vbs as Admin or schedule at user logon with task scheduler, making sure the process is started as admin

## Buy me a beer
If you find this software useful you can make a donation:
XMR: 46un6TXVK5NF4y8URSXmMLasH9D1dnn4R3bxKFxQALk63d1EUQtECanPE9JaMUTAS7Bste12BVqE72WpTbXmweJhFspKHMg
