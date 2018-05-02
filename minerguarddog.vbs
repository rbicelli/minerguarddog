' minerguarddog.vbs: XMR Miner Watchdog
' (c) 2018 Riccardo Bicelli <r.bicelli@gmail.com>
' This Program is Free Software

Const VERSION = "0.10.1"

' Initialization
Const DEVCON_SLEEP = 2
Const OVERDRIVENTOOL_FIXED_ARGS = " -consoleonly"
Const HTTP_TIMEOUT = 2
Const HTTP_ATTEMPTS = 3

'Card Array Position
Const P_CARD_NAME = 0
Const P_CARD_COUNT = 1
Const P_CARD_RESTART = 2
Const P_CARD_PNPID = 3
Const P_CARD_INDEXES = 4
Const P_CARD_OTPROFILE = 5
Const P_CARD_OTOVERRIDES = 6
Const P_CARD_OTPROFILE_T = 7
Const P_CARD_OTOVERRIDES_T = 8
Const P_CARD_TEMP_LIMIT = 9

' Timings
Dim timeWaitStart, timeWaitReboot, timeWaitMinerStart, timeSleepCycle, timeoutMinerRestartReset
Dim maxMinerRestartAttempts

'Ini File Variables
Dim IniFile
Dim logfile

'Miner
Dim miner_section
Dim hashrate_min
Dim miner_dir, miner_exe, miner_args
Dim hashrate_url, hashrate_checktype, hashrate_checkvalue
Dim miner_restart_attempts
Dim date_last_miner_restart
Dim rig_identifier

Dim monitor_only

'Temp Monitor 
Dim tempmonitor_enable, openhardwaremonitor_url, temp_fail_action

'Paths
Dim	devcon_dir, overdriventool_dir, openhardwaremonitor_dir

'Timeouts
Dim timeout_shareacceptedchange, timeout_templimit

'Notifications
Dim notifications
Dim telegram_api_key, telegram_chat_id
Dim notify_message

Dim scriptdir
Dim gWshShell

Dim cards()
Dim cards_TempOK()
ReDim appliedTimedProfiles(0)

forceCScriptExecution

scriptdir = replace(WScript.ScriptFullName,WScript.ScriptName,"")

IniFile = scriptdir & "minerguarddog.ini"

Set gWshShell = CreateObject("WScript.Shell")
gWshShell.CurrentDirectory = scriptdir

' Read Configuration from INI File
ReadConfig
notify_message = ""
Echo "MinerGuardDog Version " & VERSION, True

If ValidateConfig=False Then Wscript.Quit

Echo "------------------------------------------------------------", False
Echo "Watching Miner Program: " & miner_exe, True
Echo "Monitoring hashrate on URL: " & hashrate_url, True
Echo "Hashrate threshold set to: " & hashrate_min & " H/s", True
Echo "Logging to file: " & logfile, True

If isArray(cards) Then
	Redim cards_TempOK(ubound(cards))
	For n=0 to ubound(cards)
		cards_TempOK(n) = True
		c = split(cards(n),"|")
		Echo "Monitoring video card: " & c(P_CARD_NAME) & ", " & c(P_CARD_COUNT) & "x (" & c(P_CARD_PNPID) & ")", True
	Next
Else
	Echo "No video card defined. Monitoring Disabled", True
End If

Echo "------------------------------------------------------------", False

'Grace period for stopping watchdog (in case of bootloop caused by a malfunction or misconfiguration)
Echo "Waiting " & timeWaitStart & " seconds before starting watchdog", False

Sleep timeWaitStart

Echo "Starting Watchdog ...", True

miner_paused = False
date_minerstarted = Now

' Main Loop
Dim card
Dim i,nc,m
Dim Cards_OK, Temp_OK
'Counters
Dim Counter_MinerRestart, Counter_MinerPaused, Counter_SystemReboot, Counter_TempFail, Time_Start
Dim prev_sharesaccepted
Dim date_shareacceptedchange
Dim miner_paused
Dim date_minerstarted
Dim date_minerpaused

Counter_MinerRestart = 0
Time_Start = Now

Do While True
	'Check Cards
	Cards_OK = True
	
	If isArray(cards) Then
		For i=0 to ubound(cards)
			card = split(cards(i),"|")				
			'Check Number of Cards
			nc = detectNumberOfCards(card(P_CARD_NAME)) 
			If nc <> int(card(P_CARD_COUNT)) Then
				Echo "Number of video cards mismatch (" & card(P_CARD_NAME) & ":" & nc & "/" & card(P_CARD_COUNT) & "). Rebooting system in " &  timeWaitReboot & " seconds.", True
				If monitor_only=False Then RebootSystem timeWaitReboot		
			Else
				Echo "Number of video cards is OK (" & card(P_CARD_NAME) & ": " & nc & "/" & card(P_CARD_COUNT) & ")",False
			End If
			
			'Temperature Check			
			If tempmonitor_enable Then
				checkOpenhardwaremonitor
				Temps = getUrl(openhardwaremonitor_url)
				Temps = cardTemperatures(Temps,card(P_CARD_NAME),card(P_CARD_COUNT))
				Temp_OK = True		
				For m=0 To ubound(Temps)					
					If int(Temps(m)) > int(card(P_CARD_TEMP_LIMIT)) Then						
						Echo "Card " &  card(P_CARD_NAME) & ":" & m & " Temperature is over limit " & Temps(m) & "/" & card(P_CARD_TEMP_LIMIT), Cards_TempOK(i)
						Temp_OK = False						
						If monitor_only=False then
							Select Case temp_fail_action
								case "pause-miner"
									Echo "Pausing Miner for " & timeout_templimit & " seconds", Cards_TempOK(i)
									Counter_MinerPaused = Counter_MinerPaused + 1
									miner_paused = True
									date_minerpaused = Now
								case "reboot"								
									rebootSystem
								case "shutdown"
									shutdownSystem								
							End Select
						End If
						Cards_TempOK(i) = False
					End If
				Next
				If Temp_OK Then					
					ts = join(Temps,",")
					Echo "Temperatures of video card " & card(P_CARD_NAME) &" are OK (" & right(ts,len(ts)-1) & ")", Not Cards_TempOK(i)					
					If miner_paused = True Then
						If timeoutExpired(date_minerpaused,timeout_templimit) Then
							Echo "Resuming Miner", Cards_TempOK(i)
							miner_paused = False
						End If
					End If
					Cards_TempOK(i) = True
				End If
			End If
		Next		
	End If
	
	'Check Miner
	If miner_paused=False Then
		If checkProcess(miner_exe)=False Then
			Echo "Miner process is not running or not responding", True
			If monitor_only=False Then
				If killMiner(miner_exe)=True Then 
					startMiner 
					Counter_MinerRestart = Counter_MinerRestart + 1
				Else 
					Echo "Unable to kill miner, rebooting", True
					rebootSystem timeWaitReboot
				End If
			End If
		Else
			If monitor_only=False Then ApplyTimedOverdrivenTool
		End If	
	Else
		If checkProcess(miner_exe) Then
			If killMiner(miner_exe)=False Then
				Echo "Unable to kill miner", True
				rebootSystem timeWaitReboot
			End If			
		End If
	End If
	
	'Check Hashrate
	hashrate = getHashrate(hashrate_url)	

	If miner_paused=False And hashrate <> "" And hashrate_min > 0 Then
		If (hashrate < hashrate_min) then			
				If hashrate = -1 Then
					Echo "Miner seems crashed", False
				Else
					Echo "Hashrate drop detected (" & hashrate & ")", True
				End If
				If monitor_only = False Then
					Echo "Restarting miner", True			
					If killMiner(miner_exe) Then
						startMiner
					Else
						Echo "Unable to kill miner. Rebooting", True
						RebootSystem timeWaitReboot
					End If
				End If
		Else			
			Echo "Hashrate is normal (" & hashrate & "/" & hashrate_min & ")", False
		End If
	End If
	
	EndLoop
	Sleep timeSleepCycle
Loop
' End Of Main Loop


'---------------- FUNCTION LIBRARY ----------------
Sub ReadConfig
	
	Dim n, m, p
	Dim card_count, card_restart, ot_profiles,ot_card_indexes, temp_limit, card_data
	Dim ot_or, ot_overrides, ot_profile_t, ot_overrides_t, ot_startafter
	'Miner section
	miner_section = ReadIni(IniFile,"global","miner","")

	If miner_section = "" Then
		miner_section = "miner"
	Else
		miner_section = "miner." & miner_section
	End If

	'Hashrate Treshold
	hashrate_min = Int(ReadIni(IniFile,miner_section,"hashrate_treshold",0))

	'Miner Executable
	miner_dir = ReadIni(IniFile,miner_section,"directory","")
	miner_exe = ReadIni(IniFile,miner_section,"executable","")
	miner_args = ReadIni(IniFile,miner_section,"args","")

	'URL for hashrate check, please check your port configuration in xmr-stak
	hashrate_url = ReadIni(IniFile,miner_section,"url","")
	hashrate_checktype = ReadIni(IniFile,miner_section,"check_type","")
	hashrate_checkvalue = Int(ReadIni(IniFile,miner_section,"check_value",1))

	'Log File, relative to script directory
	logfile = ReadIni(IniFile,"global","logfile","minerguarddog.log")

	n = 1
	While n<>-1
		inisection = "videocard_" & n 
		card_name = ReadIni(IniFile,inisection,"name","")
		ot_overrides = ""
		If card_name = "" Then
			n = -1
		Else
			card_count =  ReadIni(IniFile,inisection,"count","1")
			card_restart =  ReadIni(IniFile,inisection,"restart","False")		
			ot_profile =  ReadIni(IniFile,inisection,"overdriventool_profile","")
			ot_card_indexes = ReadIni(IniFile,inisection,"overdriventool_card_indexes","")
			temp_limit =  ReadIni(IniFile,inisection,"temp_limit","90")		
			card_data = detectCardsData(card_name)
			
			For m=1 to card_count
				ot_or = ReadIni(IniFile,inisection,"overdriventool_profile_" & m,"")			
				If ot_or <> "" Then
					ot_overrides = ot_overrides & m & ":" & ot_or & ";"
				End If			
			Next						
			ot_overrides = stripLastChar(ot_overrides)
			
			'Load Timed Profiles From INI
			p=1
			ot_profile_t=""
			ot_overrides_t=""
			While p<>-1			
				stringa = ReadIni(IniFile,inisection,"overdriventool_profile_t" & p ,"")			
				If stringa<>"" Then					
					ot_startafter = ReadIni(IniFile,inisection,"overdriventool_profile_t" & p & "_after",60)
					ot_profile_t = ot_profile_t & p & ":" & stringa & ":" & ot_startafter & ";"													
					For m=1 to card_count
						ot_or = ReadIni(IniFile,inisection,"overdriventool_profile_t" & p & "_" & m,"")			
						If ot_or <> "" Then						
							ot_overrides_t = ot_overrides_t & p & ":" & m & ":" & ot_or & ";"
						End If			
					Next
					p=p+1
				Else
					p=-1
				End If
			Wend
			ot_profile_t = stripLastChar(ot_profile_t)
			ot_overrides_t = stripLastChar(ot_overrides_t)
			
			Redim Preserve cards(n-1)		
			cards(n-1) = card_name & "|" & card_count & "|" & card_restart & "|" & card_data & "|" & ot_card_indexes & "|" & ot_profile & "|" & ot_overrides & "|" & ot_profile_t & "|" & ot_overrides_t & "|" & temp_limit & "|"
			
			n=n+1
		End If
	Wend

	'Temperature Monitoring
	tempmonitor_enable = Sbool(ReadIni(IniFile,"tempmonitor","enable",false))
	openhardwaremonitor_url = ReadIni(IniFile,"tempmonitor","url","")
	temp_fail_action = ReadIni(IniFile,"tempmonitor","temp_fail_action","pause-miner")

	'Paths
	devcon_dir = ReadIni(IniFile,"paths","devcon_dir",scriptdir)
	overdriventool_dir = ReadIni(IniFile,"paths","overdriventool_dir",scriptdir)
	openhardwaremonitor_dir = ReadIni(IniFile,"tempmonitor","openhardwaremonitor_dir",scriptdir & "openhardwaremonitor")

	'Global Settings
	timeWaitStart = ReadIni(IniFile,"global","time_waitstart", 15)
	timeWaitMinerStart = ReadIni(IniFile,"global","time_waitminerstart", 60)
	timeWaitReboot = ReadIni(IniFile,"global","time_waitreboot", 15)
	timeSleepCycle = ReadIni(IniFile,"global","time_checkinterval", 10)
	timeoutMinerRestartReset = ReadIni(IniFile,"global","timeout_miner_restart_reset", 300)
	timeout_shareacceptedchange = Int(ReadIni(IniFile,"global","timeout_shareacceptedchange", 300))
	timeout_templimit = Int(ReadIni(IniFile,"global","timeout_templimit", 180))
	maxMinerRestartAttempts = ReadIni(IniFile,"global","max_miner_restart_attempts", 3)
		
	monitor_only = sBool(ReadIni(IniFile,"global","monitor_only", false))
		
	'Notifications
	rig_identifier = ReadIni(Inifile,"global","rig_identifier","My Rig")
	notifications = ReadIni(Inifile,"global","notifications","disabled")
	If notifications="telegram" Then
		telegram_api_key = ReadIni(IniFile,"notifications.telegram","api_key","")
		telegram_chat_id = ReadIni(IniFile,"notifications.telegram","chat_id","")
	End If
	
	ReadPersistentData
End Sub

Sub ReadPersistentData()
	Counter_SystemReboot = Int(ReadIni(Inifile,"data","Counter_SytemReboot","0"))
End Sub

Sub WritePersistentData()
	WriteIni IniFile,"data","Counter_SystemReboot",Counter_SystemReboot
End Sub

Function getHashrate (url)		
	On Error Resume Next
	Dim hashrate,response
	Dim p1,p2,slen,stringa
	hashrate=""
	response =	getUrl(url)					
	If response <> "" Then	
		Select Case hashrate_checktype
			Case "xmr-stak"				
				p1 = instr(1,response,"<tr><th>Totals:</th>")
				If hashrate_checkvalue=1 Then 'Last 60s									
					slen = 9
					p1 = instr (p1,response,"</td><td>")
					p2 = instr (p1+1,response,"</td>")					
				Else 'Last 15m					
					slen = 20
					p2 = instr(p1,response,"</tr><tr>")					
				End If
				stringa = Mid(response,p1+slen,p2-p1-slen)				
				p1=instrrev(stringa,"<td>")
				hashrate = Right(stringa,len(stringa)-p1+1)
				hashrate = replace(hashrate,"<td>","")
				hashrate = trim(replace(hashrate,"</td>",""))
				hashrate = left(hashrate, instr(1,hashrate,".")-1)
				hashrate = int(hashrate)
			Case "cast-xmr"
				p1 = instr(1,response,"""total_hash_rate_avg"":")
				p2 = instr(p1,response,",")
				stringa = Trim(Mid(response,p1+22,p2-p1-22))
				hashrate = int(int(stringa)/1000)
				'Check Shares Accepted
				p1 = instr(1,response,"""num_accepted"":")
				p2 = instr(p1,response,",")
				stringa = Trim(Mid(response,p1+15,p2-p1-15))
				echo "Share Accepted: " & stringa,False
				If prev_sharesaccepted = stringa Then					
					If timeoutExpired(date_shareacceptedchange,timeout_shareacceptedchange) Then
						Echo "cast-xmr is not submitting hashes",True
						hashrate = -1
					End If
				Else
					date_shareacceptedchange = Now
					prev_sharesaccepted = stringa
				End If					
		End Select
	else		
		hashrate = -1
	end if

	getHashrate = hashrate
End Function

Function getUrl (url)
	On Error Resume Next
	Dim req, lTimeout
	Dim i
	Set req = CreateObject("WinHttp.WinHttpRequest.5.1")
	for i=1 to HTTP_ATTEMPTS
		'Timeout values are in milli-seconds
		lTimeout = HTTP_TIMEOUT * 1000		
		req.setTimeOuts lTimeout, lTimeout, lTimeout, lTimeout
		req.open "GET", url, False
		req.send	
		
		If err=0 Then		
			getUrl = req.responseText
			Exit For
		else		
			getUrl = ""
		end if
	Next	
End Function

Function detectNumberofCards(strName)
On Error Resume Next
Dim NumOfCards, cI, oI,oWMI
Set oWMI = GetObject("winmgmts:\\.\root\cimv2")
	NumOfCards=0
	Set cI = oWMI.ExecQuery ("Select * from Win32_VideoController")
	For Each oI in cI
		If lcase(oI.Name)=lcase(strName) Then
			NumOfCards=NumOfCards+1			
		End If
	Next
	detectNumberOfCards=NumOfCards
End Function

Function detectCardsData(strName)
On Error Resume Next
	Dim ci, card_indexes, pnp_id, oWMI
	Set oWMI = GetObject("winmgmts:\\.\root\cimv2")
	ci = 0
	card_indexes = ""
	pnp_id = ""
	Set colItems = oWMI.ExecQuery ("Select * from Win32_VideoController")
	For Each objItem in colItems		
		If lcase(objItem.Name)=lcase(strname) Then			
			'Add Index
			card_indexes = card_indexes & ci & ","
			If pnp_id="" Then
				'Detect PNP ID for Devcon
				pnp_id = objItem.PNPDeviceID				
				p1 = instr(1,pnp_id,"&")
				p2 = instr(p1+1,pnp_id,"&")								
				pnp_id = left(pnp_id,p2-1)
			End If
		End If
		ci = ci + 1
	Next
	If card_indexes<>"" then 
		card_indexes = stripLastChar(card_indexes)
		detectCardsData = pnp_id '& "|" & card_indexes
	End If
End Function

Sub writeLog(stringa)
	Dim fso
	Set fso = CreateObject("Scripting.FileSystemObject")
	fso.OpenTextFile(scriptdir & "\" & logfile, 8, True).WriteLine Now & ": " & stringa
End Sub

Sub Echo(stringa, logToFile)
	Wscript.Echo Now & ": " & stringa	
	if logToFile = True Then 
		notify_message = notify_message & stringa & VbCrLf
		writeLog stringa
	End If
End Sub

Function GetParentProcessId()
    Dim processesList, process
    Set processesList = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
    Set processesList = processesList.ExecQuery("SELECT * FROM Win32_Process WHERE (Name = 'cscript.exe') AND Commandline LIKE '%"+WScript.ScriptName+"%'" )
    For Each process in processesList
        GetParentProcessId = process.ParentProcessId
    Next 
End Function

Sub forceCScriptExecution
    Dim Arg, Str
    If Not LCase( Right( WScript.FullName, 12 ) ) = "\cscript.exe" Then
        For Each Arg In WScript.Arguments
            If InStr( Arg, " " ) Then Arg = """" & Arg & """"
            Str = Str & " " & Arg
        Next
        CreateObject( "WScript.Shell" ).Run _
            "cscript //nologo """ & _
            WScript.ScriptFullName & _
            """ " & Str
        WScript.Quit
    End If
End Sub

Sub Sleep(Seconds)
	Wscript.Sleep 1000 * Seconds
End Sub

Sub RebootSystem(SleepSecs)
	Dim objWMIService, colOperatingSystems, objOperatingSystem
	Echo "Rebooting in " & SleepSecs & " seconds", True
	Sleep(SleepSecs)
	Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate,(Shutdown)}!\\.\root\cimv2")
	Set colOperatingSystems = objWMIService.ExecQuery("Select * from Win32_OperatingSystem")
	For Each objOperatingSystem in colOperatingSystems
	    	objOperatingSystem.Reboot()
	Next
	EndLoop
	Wscript.Quit
End Sub

Sub ShutDownSystem(SleepSecs)
	Dim objWMIService, colOperatingSystems, objOperatingSystem
	Echo "Shutting down in " & SleepSecs & " seconds", True
	Sleep(SleepSecs)
	Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate,(Shutdown)}!\\.\root\cimv2")
	Set colOperatingSystems = objWMIService.ExecQuery("Select * from Win32_OperatingSystem")
	For Each objOperatingSystem in colOperatingSystems
	    	objOperatingSystem.Reboot()
	Next
	EndLoop
	Wscript.Quit
End Sub

Function KillMiner(exeName)	
	Dim i
	For i=0 To 5		
		gWshShell.Run "TASKKILL /F /IM " & exeName, 0, True
		If checkProcess(exeName)=False Then
			KillMiner = True
			Exit Function
		End If
		Sleep 1
	Next
	KillMiner = False	
End Function

Function checkProcess(procName)
	On Error Resume Next
	Dim oWMI, objDictionary, colProcesses, objProcess, colThreads, objThread
	Dim intProcessID, strProcessName
	checkProcess = False
	Set objDictionary = CreateObject("Scripting.Dictionary")
	Set oWMI = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
	Set colProcesses = oWMI.ExecQuery("Select * from Win32_Process Where Name = '" & procName & "'")
	
	For each objProcess in colProcesses 
    		objDictionary.Add objProcess.ProcessID, objProcess.Name 			
	Next
	For each objProcess in colProcesses
		Set colThreads = oWMI.ExecQuery("Select * from Win32_Thread where ProcessHandle = '" & objProcess.ProcessID & "'")
		For each objThread in colThreads
			intProcessID = CInt(objThread.ProcessHandle)
			strProcessName = objDictionary.Item(intProcessID)		
			If objThread.ThreadState = 8 then
				checkProcess = False
				Exit For
			Else
				checkProcess = True
			End If
		Next
	Next
	If Err<>0 Then
		'The above method sometimes is unreliable, so let's check 		
		'the process with Tasklist.exe
		If GetProcessId(procName)>0 Then checkProcess=True
	End If
End Function

Function GetProcessId(imageName)
    Dim command, output, tasklist, tasks, i, cols
	
	GetProcessId=0
    
    command = "tasklist /V /FO csv"
    command = command & " /FI ""IMAGENAME eq " + imageName + """"
    
    output = Trim(Shell(command))
    tasklist = Split(output, vbNewLine)

    ' starting at 1 skips first line (it contains the column headings only)
    For i = 1 To UBound(tasklist) - 1
        cols = Split(tasklist(i), """,""")
        ' a line is expected to have 9 columns (0-8)
        If UBound(cols) = 8 Then
            GetProcessId = Trim(cols(1))
            Exit For
        End If
    Next	
End Function

Function Shell(cmd)
    Shell = WScript.CreateObject("WScript.Shell").Exec(cmd).StdOut.ReadAll()
End Function

Sub startMiner()
	Dim overdriventool_cmd
	Dim n, m, p
	Dim ot_or, ot_ori, idx
	Dim prevdir
	Dim c, card_profile
	
	overdriventool_cmd = ""
	
	If isArray(cards) Then
		'Restart Cards with Devcon
		Echo "Restarting Cards", True
		For n=0 To ubound(cards)			
			c = split(cards(n),"|")			
			If sBool(c(P_CARD_RESTART))=True Then			
				Echo "Disabling " & c(P_CARD_NAME) & ": " & c(P_CARD_PNPID), False	
				gWshShell.Run devcon_dir & "\DEVCON.EXE disable """ & c(P_CARD_PNPID) & """", True
				Sleep DEVCON_SLEEP
				Echo "Enabling " & c(P_CARD_NAME) & ": " & c(P_CARD_PNPID), False
				gWshShell.Run devcon_dir & "\DEVCON.EXE enable """ & c(P_CARD_PNPID) & """", True
			End If
		Next
		Echo "Waiting Devices to settle", False
		Sleep DEVCON_SLEEP		
	
		'Build Overdriventool Command Line
		For n=0 to ubound(cards)
			c = split(cards(n),"|")
			If c(P_CARD_OTPROFILE) <> "" Then
				idx = split(c(P_CARD_INDEXES),",")			
				ot_or = split(c(P_CARD_OTOVERRIDES),";")			
				For m=0 to ubound(idx)
					card_profile =  c(P_CARD_OTPROFILE)
					For p=0 to ubound(ot_or)
						ot_ori = split(ot_or(p),":")					
						If ot_ori(0) = idx(m) Then
							card_profile = ot_ori(1)
						End If
					Next
					overdriventool_cmd = overdriventool_cmd & " -p" & idx(m) & card_profile				
				Next
			End If		
		Next
		
		If overdriventool_cmd<>"" Then
			Echo "Applying Overdriventool Profiles", True
			Echo "Executing Command " & overdriventool_dir & "\OVERDRIVENTOOL.EXE " & OVERDRIVENTOOL_FIXED_ARGS & " " & overdriventool_cmd, True
			gWshshell.Run overdriventool_dir & "\OVERDRIVENTOOL.EXE " & OVERDRIVENTOOL_FIXED_ARGS & " " & overdriventool_cmd, True
		End If
	
	End If
	
	prevdir = gWshShell.CurrentDirectory
	gWshShell.CurrentDirectory = scriptdir & "\" & miner_dir
	gWshShell.Run miner_exe & " " & miner_args, 1, False
	gWshShell.CurrentDirectory = prevdir
	Echo "Miner Started, waiting " & timeWaitMinerStart & " seconds", True
	Sleep timeWaitMinerStart
	
	date_minerstarted = now
	'Reset Counters
	resetCounters
End Sub


Sub ApplyTimedOverdrivenTool()
	Dim n, p, q, c, profi, bProfile_applies, AppliedProfile, idx, ot_or, ot_ori, card_profile, overdriventool_cmd
	Const SP_PROFINDEX = 0
	Const SP_PROFNAME = 1
	Const SP_TIME = 2

	Const SP_CARDINDEX=1
	Const SP_OVERRIDEINDEX=2 

	overdriventool_cmd = ""

	bProfile_applies = False
	'Build Overdriventool Command Line
	For n=0 to ubound(cards)
		c = split(cards(n),"|")
		If c(P_CARD_OTPROFILE_T) <> "" Then				
			op = split(c(P_CARD_OTPROFILE_T),";")			
			For m=0 to ubound(op)
				profi=split(op(m),":")				
				If inArray(profi(SP_PROFINDEX),appliedTimedProfiles)=False And timeoutExpired(date_minerstarted,profi(SP_TIME)) Then
					bProfile_applies=True					
					'Profile has to be applied					
					AppliedProfile = profi(SP_PROFINDEX)																		
					idx = split(c(P_CARD_INDEXES),",")								
					'Override of current profile					
					ot_or = split(c(P_CARD_OTOVERRIDES_T),";")			
					For p=0 to ubound(idx)											
						card_profile = profi(SP_PROFNAME)
						For q=0 to ubound(ot_or)																					
							ot_ori = split(ot_or(q),":")														
							If int(ot_ori(SP_PROFINDEX))=int(profi(SP_PROFINDEX)) and int(ot_ori(SP_CARDINDEX))=int(idx(p)) Then								
								card_profile = ot_ori(SP_PROFNAME+1)								
							End If
						Next
						overdriventool_cmd = overdriventool_cmd & " -p" & idx(p) & card_profile										
					Next										
				End	If
				if bProfile_applies Then Exit For
			Next
		End If
		if bProfile_applies Then Exit For
	Next
	If bProfile_applies Then	
		Echo "Applying Stepping Overdriventool Profiles", True
		Echo "Executing Command " & overdriventool_dir & "\OVERDRIVENTOOL.EXE " & OVERDRIVENTOOL_FIXED_ARGS & " " & overdriventool_cmd, True
		gWshShell.Run overdriventool_dir & "\OVERDRIVENTOOL.EXE " & OVERDRIVENTOOL_FIXED_ARGS & " " & overdriventool_cmd, 0, True
		Redim Preserve appliedTimedProfiles(ubound(appliedTimedProfiles)+1)
		appliedTimedProfiles(ubound(appliedTimedProfiles)) = AppliedProfile
	End If
End Sub

Function ReadIni( myFilePath, mySection, myKey, myDefault )
    ' This function returns a value read from an INI file
    '
    ' Arguments:
    ' myFilePath  [string]  the (path and) file name of the INI file
    ' mySection   [string]  the section in the INI file to be searched
    ' myKey       [string]  the key whose value is to be returned
    '
    ' Returns:
    ' the [string] value for the specified key in the specified section
    ' or myDefault in case of empty or non existent value   
    '
    ' Written by Keith Lacelle
    ' Modified by Denis St-Pierre and Rob van der Woude
	' Modified by Riccardo Bicelli

    Const ForReading   = 1
    Const ForWriting   = 2
    Const ForAppending = 8

    Dim intEqualPos
    Dim objFSO, objIniFile
    Dim strFilePath, strKey, strLeftString, strLine, strSection

    Set objFSO = CreateObject( "Scripting.FileSystemObject" )

    ReadIni     = ""
    strFilePath = Trim( myFilePath )
    strSection  = Trim( mySection )
    strKey      = Trim( myKey )

    If objFSO.FileExists( strFilePath ) Then
        Set objIniFile = objFSO.OpenTextFile( strFilePath, ForReading, False )
        Do While objIniFile.AtEndOfStream = False
            strLine = Trim( objIniFile.ReadLine )

            ' Check if section is found in the current line
            If LCase( strLine ) = "[" & LCase( strSection ) & "]" Then
                strLine = Trim( objIniFile.ReadLine )

                ' Parse lines until the next section is reached
                Do While Left( strLine, 1 ) <> "["
                    ' Find position of equal sign in the line
                    intEqualPos = InStr( 1, strLine, "=", 1 )
                    If intEqualPos > 0 Then
                        strLeftString = Trim( Left( strLine, intEqualPos - 1 ) )
                        ' Check if item is found in the current line
                        If LCase( strLeftString ) = LCase( strKey ) Then
                            ReadIni = Trim( Mid( strLine, intEqualPos + 1 ) )                            
                            ' Abort loop when item is found
                            Exit Do
                        End If
                    End If

                    ' Abort if the end of the INI file is reached
                    If objIniFile.AtEndOfStream Then Exit Do

                    ' Continue with next line
                    strLine = Trim( objIniFile.ReadLine )
                Loop
            Exit Do
            End If
        Loop
        objIniFile.Close
		
		if ReadIni = "" Then 
			' If empty then leave default value
			ReadIni = myDefault
		Else
			' Strip Double Quotes 
			if Left(ReadIni,1) = """" Then Readini = Right(ReadIni,len(ReadIni)-1)
			if Right(ReadIni,1) = """" Then Readini = Left(ReadIni,len(ReadIni)-1)
		End If
    Else
        WScript.Echo strFilePath & " doesn't exists. Exiting..."
        Wscript.Quit 1
    End If
End Function

Sub WriteIni( myFilePath, mySection, myKey, myValue )
    ' This subroutine writes a value to an INI file
    '
    ' Arguments:
    ' myFilePath  [string]  the (path and) file name of the INI file
    ' mySection   [string]  the section in the INI file to be searched
    ' myKey       [string]  the key whose value is to be written
    ' myValue     [string]  the value to be written (myKey will be
    '                       deleted if myValue is <DELETE_THIS_VALUE>)
    '
    ' Returns:
    ' N/A
    '
    ' CAVEAT:     WriteIni function needs ReadIni function to run
    '
    ' Written by Keith Lacelle
    ' Modified by Denis St-Pierre, Johan Pol and Rob van der Woude

    Const ForReading   = 1
    Const ForWriting   = 2
    Const ForAppending = 8

    Dim blnInSection, blnKeyExists, blnSectionExists, blnWritten
    Dim intEqualPos
    Dim objFSO, objNewIni, objOrgIni, wshShell
    Dim strFilePath, strFolderPath, strKey, strLeftString
    Dim strLine, strSection, strTempDir, strTempFile, strValue

    strFilePath = Trim( myFilePath )
    strSection  = Trim( mySection )
    strKey      = Trim( myKey )
    strValue    = Trim( myValue )

    Set objFSO   = CreateObject( "Scripting.FileSystemObject" )
    Set wshShell = CreateObject( "WScript.Shell" )

    strTempDir  = wshShell.ExpandEnvironmentStrings( "%TEMP%" )
    strTempFile = objFSO.BuildPath( strTempDir, objFSO.GetTempName )

    Set objOrgIni = objFSO.OpenTextFile( strFilePath, ForReading, True )
    Set objNewIni = objFSO.CreateTextFile( strTempFile, False, False )

    blnInSection     = False
    blnSectionExists = False
    ' Check if the specified key already exists
    blnKeyExists     = ( ReadIni( strFilePath, strSection, strKey, "" ) <> "" )
    blnWritten       = False

    ' Check if path to INI file exists, quit if not
    strFolderPath = Mid( strFilePath, 1, InStrRev( strFilePath, "\" ) )
    If Not objFSO.FolderExists ( strFolderPath ) Then
        WScript.Echo "Error: WriteIni failed, folder path (" _
                   & strFolderPath & ") to ini file " _
                   & strFilePath & " not found!"
        Set objOrgIni = Nothing
        Set objNewIni = Nothing
        Set objFSO    = Nothing
        WScript.Quit 1
    End If

    While objOrgIni.AtEndOfStream = False
        strLine = Trim( objOrgIni.ReadLine )
        If blnWritten = False Then
            If LCase( strLine ) = "[" & LCase( strSection ) & "]" Then
                blnSectionExists = True
                blnInSection = True
            ElseIf InStr( strLine, "[" ) = 1 Then
                blnInSection = False
            End If
        End If

        If blnInSection Then
            If blnKeyExists Then
                intEqualPos = InStr( 1, strLine, "=", vbTextCompare )
                If intEqualPos > 0 Then
                    strLeftString = Trim( Left( strLine, intEqualPos - 1 ) )
                    If LCase( strLeftString ) = LCase( strKey ) Then
                        ' Only write the key if the value isn't empty
                        ' Modification by Johan Pol
                        If strValue <> "<DELETE_THIS_VALUE>" Then
                            objNewIni.WriteLine strKey & "=" & strValue
                        End If
                        blnWritten   = True
                        blnInSection = False
                    End If
                End If
                If Not blnWritten Then
                    objNewIni.WriteLine strLine
                End If
            Else
                objNewIni.WriteLine strLine
                    ' Only write the key if the value isn't empty
                    ' Modification by Johan Pol
                    If strValue <> "<DELETE_THIS_VALUE>" Then
                        objNewIni.WriteLine strKey & "=" & strValue
                    End If
                blnWritten   = True
                blnInSection = False
            End If
        Else
            objNewIni.WriteLine strLine
        End If
    Wend

    If blnSectionExists = False Then ' section doesn't exist
        objNewIni.WriteLine
        objNewIni.WriteLine "[" & strSection & "]"
            ' Only write the key if the value isn't empty
            ' Modification by Johan Pol
            If strValue <> "<DELETE_THIS_VALUE>" Then
                objNewIni.WriteLine strKey & "=" & strValue
            End If
    End If

    objOrgIni.Close
    objNewIni.Close

    ' Delete old INI file
    objFSO.DeleteFile strFilePath, True
    ' Rename new INI file
    objFSO.MoveFile strTempFile, strFilePath

    Set objOrgIni = Nothing
    Set objNewIni = Nothing
    Set objFSO    = Nothing
    Set wshShell  = Nothing
End Sub

Function sBool(sValue)
	' Easy String to boolean
	if lcase(sValue)="true" Or lcase(sValue)="yes" Or sValue="1" Then 
		sBool=True
	Else
		sBool = False
	End If
End Function

Function validateConfig()
	Dim fso
	Set fso = CreateObject("Scripting.FileSystemObject")
	validateConfig = True
	
	' Miner Executable
	If fso.FileExists(scriptdir & miner_dir & "\" & miner_exe) = False Then
		Echo "Error: Miner executable " & miner_dir & "\" & miner_exe & " doesn't exist.", False
		validateConfig = False
	End If		
	
	'Overdriventool
	If fso.FileExists(overdriventool_dir & "\overdriventool.exe") = False Then
		Echo "Error: Overdriventool.exe executable doesn't exist in " & overdriventool_dir, False
		ValidateConfig = False
	End If
	
	'Devcon
	If fso.FileExists(devcon_dir & "\devcon.exe") = False Then
		Echo "Warning: Devcon.exe executable doesn't exist in " & devcon_dir, False		
	End If
	
	'Temperature Monitor
	If tempmonitor_enable Then
		If fso.FileExists(openhardwaremonitor_dir & "\openhardwaremonitor.exe") = False Then
			Echo "Warning: Openhardwaremonitor.exe executable doesn't exist in " & openhardwaremonitor_dir, False
			tempmonitor_enable = False
		End If
	End If
	
	'Warnings
	If hashrate_min<=0 Then
		Echo "Warning: Minimum Hashrate threshold in invalid. Hashrate threshold check is disabled", True
	End If	
	
End Function

Function timeElapsed(referenceTime)
	timeElapsed = datediff("s",referenceTime,now)
End Function

Function timeoutExpired(referenceTime,TimeoutValue)	
	If datediff("s",referenceTime,now) > int(timeoutValue) Then		
		timeoutExpired = True
	Else
		timeoutExpired = False
	End If
End Function

Sub resetCounters
	'Reset Counters
	date_shareacceptedchange = now	
End Sub

function cardTemperatures(strjson,strName,cCount)	
	Dim str, n, s1, Temp
	str=lcase(strjson)	
	s1 = 1
	Redim Temps(cCount)
	For n=1 to cCount		
		Temp=0
		If s1>0 Then
			s1 = instr(s1,str,lcase(strName))
			If s1>0 Then
				s1 = instr(s1,str,"temperatures")
				s1 = instr(s1,str,"gpu core")
				s1 = instr(s1,str,"value") + 9
				if s1>0 Then
					Temp = mid(str, s1, instr(s1+1,str,"""")-s1)
					Temp = trim(Temp)
					Temp = left(Temp,(instr(1,Temp," ")))				
				End If
				If IsNumeric(Temp) Then 
					Temp=cdbl(temp)
				End If				
			End If
		End If
			Temps(n)=Temp				
	Next	 
	cardTemperatures = Temps
end function

Sub checkOpenhardwaremonitor	
	Dim n
	For n=1 to 3		
		If checkProcess("openhardwaremonitor.exe") = False Then
			Echo "Starting Openhardwaremonitor", True
			gWshShell.Run openhardwaremonitor_dir & "\openhardwaremonitor.exe",1,False
			Sleep 0.5
		Else
			Exit For
		End If		
	Next
End Sub

Function stripLastChar(stringa)
If stringa <> "" Then 
	stripLastChar = left(stringa,len(stringa)-1)
Else
	stripLastChar = ""
End If
End Function

Function inArray(needle,haystack)
	inArray = False
	Dim n
	For n=0 to ubound(haystack)
		if haystack(n)=needle Then inArray = True
	Next	
End Function

Function stringIsAplhaFirst(string1,string2)
	'Alphabetical sorting with number last
	Dim bRet
	bRet = True
	Const S_ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
	If len(string1)>len(string2) Then
		sl = len(string2)
	Else
		sl = len(string1)
	End If
	For i=1 to sl
		c1 = ucase(mid(string1,i,1))
		c2 = ucase(mid(string2,i,1))	
		If instr(S_ALPHA,c1)>instr(S_ALPHA,c2) Then
			bRet = False
			Exit For
		End If	
	Next
strSort=bRet
End Function

'Telegram Monitoring
Function telegramBotSend(sApiKey,sChatID,sMessage)
  Dim oHTTP
  Dim sUrl, sRequest
  sUrl = "https://api.telegram.org/bot" & sApiKey & "/sendMessage"
  sRequest = "text=" & sMessage & "&chat_id=" & sChatID
  set oHTTP = CreateObject("Microsoft.XMLHTTP")
  oHTTP.open "POST", sUrl,false
  oHTTP.setRequestHeader "Content-Type", "application/x-www-form-urlencoded"
  oHTTP.setRequestHeader "Content-Length", Len(sRequest)
  oHTTP.send sRequest
  telegramBotSend = oHTTP.responseText
 End Function
 
 Sub sendReport(sMessage)
	sMessage = "Rig ID: " & rig_identifier & VbCrLf & sMessage
	If notifications = "telegram" Then
		echo "Sending Notification to Telegram", False
		telegramBotSend telegram_api_key, telegram_chat_id, sMessage		
	End If
 End Sub
 
 Sub EndLoop
	If notify_message<>"" then 		
		sendReport notify_message
		notify_message = ""
	End If
	WritePersistentData
 End Sub