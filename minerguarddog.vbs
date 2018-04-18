' minerguarddog.vbs: XMR Miner Watchdog
' (c) 2018 Riccardo Bicelli <r.bicelli@gmail.com>
' This Program is Free Software
' Version 0.9.1

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
Const P_OT_OVERRIDES = 6

Dim timeWaitStart
Dim timeWaitReboot
Dim timeWaitMinerStart
Dim timeSleepCycle

Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")

forceCScriptExecution
CheckForOtherInstances

scriptdir = replace(WScript.ScriptFullName,WScript.ScriptName,"")

IniFile = scriptdir & "minerguarddog.ini"

Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = scriptdir

Set fso = CreateObject("Scripting.FileSystemObject")

'---------------------------------------------------
' Load Configuration
'---------------------------------------------------

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
		ot_profile =  ReadIni(IniFile,inisection,"overdrivent_profile","")		
		card_data = detectCardsData(card_name)
		
		For m=1 to card_count
			ot_or = ReadIni(IniFile,inisection,"overdrivent_profile_" & m,"")			
			If ot_or <> "" Then
				ot_overrides = ot_overrides & m & ":" & ot_or & ";"
			End If			
		Next		
		If ot_overrides <> "" Then ot_overrides = left(ot_overrides,len(ot_overrides)-1)
		
		Redim Preserve cards(n-1)		
		cards(n-1) = card_name & "|" & card_count & "|" & card_restart & "|" & card_data & "|" & ot_profile & "|" & ot_overrides
		
		n=n+1
	End If
Wend

'Paths
devcon_dir = ReadIni(IniFile,"paths","devcon_dir",scriptdir)
overdriventool_dir = ReadIni(IniFile,"paths","doverdriventool_dir",scriptdir)

'Global Settings
timeWaitStart = ReadIni(IniFile,"global","time_waitminerstart", 15)
timeWaitMinerStart = ReadIni(IniFile,"global","time_waitminerstart", 60)
timeWaitReboot = ReadIni(IniFile,"global","time_waitreboot", 15)
timeSleepCycle = ReadIni(IniFile,"global","time_checkinterval", 10)
'---------------------------------------------------


Echo "------------------------------------------------------------", False
Echo "Watching Miner Program: " & miner_exe, True
Echo "Monitoring hashrate on URL: " & hashrate_url, True
Echo "Hashrate threshold set to: " & hashrate_min & " H/s", True
Echo "Logging to file: " & logfile, True
Echo "------------------------------------------------------------", False

If isArray(cards) Then
	For n=0 to ubound(cards)
		c = split(cards(n),"|")
		Echo "Monitoring video card: " & c(P_CARD_NAME) & ", " & c(P_CARD_COUNT) & "x (" & c(P_CARD_PNPID) & ")", True
	Next
Else
	Echo "No video card defined. Monitoring Disabled", True
End If

If ValidateConfig=False Then Wscript.Quit

Echo "Waiting " & timeWaitStart & " Seconds before starting watchdog", False

Sleep timeWaitStart

Echo "Starting Watchdog ...", True

Do While True
		
	'Check Number of Cards
	If isArray(cards) Then
		For n=0 to ubound(cards)
			c = split(cards(n),"|")
			nc = detectNumberOfCards(c(0)) 
			If nc <> int(c(P_CARD_COUNT)) Then
				Echo "Number of video cards mismatch (" & c(P_CARD_NAME) & ":" & nc & "/" & c(P_CARD_COUNT) & "). Rebooting system in " &  timeWaitReboot & " seconds.", True
				RebootSystem timeWaitReboot		
			Else
				Echo "Number of video cards is OK (" & c(P_CARD_NAME) & ": " & nc & "/" & c(P_CARD_COUNT) & ")",False
			End If
		Next
	End If
	
	'Check Miner
	If checkProcess(miner_exe)=False Then
		Echo "Miner process is not running or not responding, Restarting Miner", True
		If killMiner(miner_exe)=True Then 
			startMiner 
		Else 
			Echo "Unable to kill miner, rebooting", True
			rebootSystem timeWaitReboot
		End If
	Else
		Echo "Miner is Running", False		
	End If	

	'Check Hashrate
	hashrate = getHashrate(hashrate_url)	

	If hashrate <> "" And hashrate_min > 0 Then
		If (hashrate < hashrate_min) then			
				Echo "Hashrate drop detected (" & hashrate & ")", True
				Echo "Restarting miner", True			
				If killMiner(miner_exe) Then
					startMiner
				Else
					Echo "Unable to kill miner. Rebooting", True
					RebootSystem timeWaitReboot
				End If			
		Else			
			Echo "Hashrate is normal (" & hashrate & "/" & hashrate_min & ")", False
		End If
	End If

	Sleep timeSleepCycle
Loop

'---------------- FUNCTION LIBRARY ----------------

Function getHashrate (url)
	On Error Resume Next
	
	response =	getUrl(url)			
	
	If response <> "" Then	
		Select Case hashrate_checktype
			Case "xmr-stak"
				p1 = instr(1,response,"<tr><th>Totals:</th>")
				p2 = instr(p1,response,"</tr><tr>")

				stringa = Mid(response,p1+20,p2-p1-20)

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
				
		End Select
	else		
		hashrate = -1
	end if

	getHashrate = hashrate
End Function

Function getUrl (url)
	On Error Resume Next
	
	Set req = CreateObject("WinHttp.WinHttpRequest.5.1")
	for n=1 to HTTP_ATTEMPTS
		'Timeout values are in milli-seconds
		lResolve = HTTP_TIMEOUT * 1000
		lConnect = HTTP_TIMEOUT * 1000
		lSend = HTTP_TIMEOUT * 1000
		lReceive = HTTP_TIMEOUT * 1000 'waiting time to receive data from server
		req.setTimeOuts lResolve, lConnect, lSend, lReceive
		req.open "GET", url, False
		req.send	
		
		If err=0 Then		
			getUrl = req.responseText
			Exit For
		else		
			getUrl = ""
		end if
	Next
	getHashrate = hashrate
End Function

Function detectNumberofCards(strName)
On Error Resume Next
	NumOfCards=0
	Set colItems = objWMIService.ExecQuery ("Select * from Win32_VideoController")
	For Each objItem in colItems
		If lcase(objItem.Name)=lcase(strname) Then
		NumOfCards=NumOfCards+1			
		End If
	Next
	detectNumberOfCards=NumOfCards
End Function

Function detectCardsData(strName)
On Error Resume Next	
	ci = 0
	card_indexes = ""
	pnp_id = ""
	Set colItems = objWMIService.ExecQuery ("Select * from Win32_VideoController")
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
		card_indexes = left(card_indexes,len(card_indexes)-1)
		detectCardsData = pnp_id & "|" & card_indexes
	End If
End Function

Sub writeLog(stringa)
	fso.OpenTextFile(scriptdir & "\" & logfile, 8, True).WriteLine Now & ": " & stringa
End Sub

Sub Echo(stringa, logToFile)
	Wscript.Echo Now & ": " & stringa
	if logToFile = True Then writeLog stringa
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

Sub CheckForOtherInstances
n=0
Set colProcess = objWMIService.ExecQuery("Select * From Win32_Process where name = 'cscript.exe'") 
For Each objProcess In colProcess	
    If trim(lcase(replace(objProcess.CommandLine,"cscript",""))) = trim(lcase(Wscript.ScriptName)) Then		
		n = n+1
	End If
Next
If n>1 Then
	Echo "Another Instance of script is already running. Quitting", False
	Wscript.Quit
End If
End Sub

Sub Sleep(Seconds)
	Wscript.Sleep 1000 * Seconds
End Sub

Sub RebootSystem(SleepSecs)
	Sleep(SleepSecs)
	Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate,(Shutdown)}!\\.\root\cimv2")
	Set colOperatingSystems = objWMIService.ExecQuery("Select * from Win32_OperatingSystem")
	For Each objOperatingSystem in colOperatingSystems
	    	objOperatingSystem.Reboot()
	Next
	Wscript.Quit
End Sub

Function KillMiner(exeName)	
	For n=0 To 5		
		WshShell.Run "TASKKILL /F /IM " & exeName,0,True
		If checkProcess(exeName)=False Then
			KillMiner = True
			Exit Function
		End If
		Sleep 1
	Next
	KillMiner = False	
End Function

Function checkProcess(procName)
	checkProcess = False
	Set objDictionary = CreateObject("Scripting.Dictionary")
	Set objWMIService = GetObject("winmgmts:" & "{impersonationLevel=impersonate}!\\" & "." & "\root\cimv2")
	Set colProcesses = objWMIService.ExecQuery("Select * from Win32_Process Where Name = '" & procName & "'")
	
	For each objProcess in colProcesses 
    		objDictionary.Add objProcess.ProcessID, objProcess.Name 
	Next
	For each objProcess in colProcesses
		Set colThreads = objWMIService.ExecQuery("Select * from Win32_Thread where ProcessHandle = '" & objProcess.ProcessID & "'")
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
End Function

Sub startMiner()
	overdriventool_cmd = ""
	
	If isArray(cards) Then
		'Restart Cards with Devcon
		Echo "Restarting Cards", True
		For n=0 To ubound(cards)			
			c = split(cards(n),"|")			
			If sBool(c(P_CARD_RESTART))=True Then			
				Echo "Disabling " & c(P_CARD_NAME) & ": " & c(P_CARD_PNPID), False	
				WshShell.Run devcon_dir & "\DEVCON.EXE disable """ & c(P_CARD_PNPID) & """", 0,True
				Sleep DEVCON_SLEEP
				Echo "Enabling " & c(P_CARD_NAME) & ": " & c(P_CARD_PNPID), False
				WshShell.Run devcon_dir & "\DEVCON.EXE enable """ & c(P_CARD_PNPID) & """", 0,True
			End If
		Next
		Echo "Waiting Devices to settle", False
		Sleep DEVCON_SLEEP		
	
		'Build Overdriventool Command Line
		For n=0 to ubound(cards)
			c = split(cards(n),"|")
			If c(P_CARD_OTPROFILE) <> "" Then
				idx = split(c(P_CARD_INDEXES),",")			
				ot_or = split(c(P_OT_OVERRIDES),";")			
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
			Echo "Executing Command " & overdriventool_dir & "\OVERDRIVENTOOL.EXE " & OVERDRIVENTOOL_FIXED_ARGS & " " & overdriventool_cmd, False
			WshShell.Run overdriventool_dir & "\OVERDRIVENTOOL.EXE " & OVERDRIVENTOOL_FIXED_ARGS & " " & overdriventool_cmd, 0, True
		End If
	
	End If
	
	prevdir = wshShell.CurrentDirectory
	wshShell.CurrentDirectory = scriptdir & "\" & miner_dir
	WshShell.Run miner_exe & " " & miner_args, 1, False
	wshShell.CurrentDirectory = prevdir
	Echo "Miner Started", True
	Sleep timeWaitMinerStart

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

Function sBool(sValue)
	' Easy String to boolean
	if lcase(sValue)="true" Or lcase(sValue)="yes" Or sValue="1" Then 
		sBool=True
	Else
		sBool = False
	End If
End Function

Function validateConfig()
	validateConfig = True
	
	' Miner Executable
	If fso.FileExists(scriptdir & miner_dir & "\" & miner_exe) = False Then
		Echo "Error: Miner executable " & miner_dir & "\" & miner_exe & " doesn't exist.", False
		validateConfig = False
	End If
	
	'Devcon
	If fso.FileExists(devcon_dir & "\devcon.exe") = False Then
		Echo "Error: Devcon.exe executable doesn't exist in " & devcon_dir, False
		ValidateConfig = False
	End If
	
	'Overdriventool
	If fso.FileExists(overdriventool_dir & "\overdriventool.exe") = False Then
		Echo "Error: Overdriventool.exe executable doesn't exist in " & overdriventool_dir, False
		ValidateConfig = False
	End If
	
	'Warnings
	If hashrate_min<=0 Then
		Echo "Warning: Minimum Hashrate threshold in invalid. Hashrate threshold check is disabled", True
	End If	
	
End Function
