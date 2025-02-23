function postprocess{invoke-command -ScriptBlock {tgw postprocess}}

function tgw ($rawcommand){
    $rawcommands= @("status","status-watch","sync","archive-results","reset","postprocess","beat-sync","Splunk-sync")

    #Process raw commands from a native powershell prompt
    if ($rawcommand){
        if ($rawcommands -notcontains $rawcommand){
            clear-host
            write-output "Invalid switch"
            sleep 1
            clear
            break
        }
    }

    #Check language mode and ensure that it is full language mode, if not, report an error
    if ($ExecutionContext.SessionState.LanguageMode -ne "FullLanguage"){
        clear-host
        write-host "Language mode is $($ExecutionContext.SessionState.LanguageMode)" -ForegroundColor Red
        Write-Host "You must set language mode to FullLanguage. `n" -ForegroundColor red
        pause
        break
    }

    #Check Winrm and report an error if not enabled
    if ($(get-service -name winrm).status -eq "Stopped"){
        clear-host
        write-host "[ERROR]" -ForegroundColor Red
        write-output "WinRM service is not running"
        Write-Output "You must start WinRM"
        Write-Output 'Example: start-service -name WinRM'
        Write-Output 'Example: enable-psremoting -force'
        write-output " "
        pause
        break
    }

    if ($(get-service -name winrm).status -eq "Running"){
        #Check Trustedhosts
        if (!$(get-item WSMan:\localhost\Client\TrustedHosts).value){
            write-output "Trusted hosts value is null"
            write-output "You may need to set your trusted hosts value."
            write-output "Example: set-item WSMan:\localhost\Client\TrustedHosts -value * -Force"
        }
    }

    #Clean the action variable to make it available for the next action you plan on conducting
    remove-variable -name action -Force -ErrorAction SilentlyContinue

    #Builds out the default header that is displayed at the various menus
    Function Header{
        "        ================================
        ======= The Greater Wall =======
        ================================`n"    
    }

    #Creates running Opnotes file
    function LogTo-Opnotes($action){
        function get-cmdletsused($action){
            $manpage= Get-Childitem $env:USERPROFILE\Desktop\TheGreaterWall\Modules\Module_help_pages\ | where {$_.name -eq "$action-help.txt"} | get-content
            $manpage_entry= $manpage | Select-String "CmdLets used:"

            if (!$manpage_entry){
                $cmdletsused= "Information Unavailable"
            }

            if ($manpage_entry){
                $line_start= $($manpage | Select-String "CmdLets used:").LineNumber
                $line_end= $($manpage | Select-String "Output format").LineNumber -3
                $cmdletsused= $($manpage[$($line_start)..$($line_end)] | % {$_.trimstart().trimend()})-join(", ")
            }

            return $cmdletsused
        }
    
        $logfile= "$env:USERPROFILE\Desktop\TheGreaterWall\TGWLogs\OpNotes.txt"
        $date= "[ " + $((Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join "") + " ]"
        $targets= $($listofips)-join(", ")
        $cmdletsused= get-cmdletsused $action  
    
        Write-output "*************************************" | out-file -Append -FilePath $logfile
        Write-Output "$date" | out-file -Append -FilePath $logfile
        Write-Output "Action: $action" | out-file -Append -FilePath $logfile
        Write-Output "Targets: $targets" | out-file -Append -FilePath $logfile
        Write-Output "Powershell Commands used: $cmdletsused" | out-file -Append -FilePath $logfile
        Write-Output "*************************************" | out-file -Append -FilePath $logfile
    }

    #Imports AD module
    function Import-ActiveDirectory{
        if ($activedirectoryconfiguration -eq "0" -or !$activedirectoryconfiguration){
            clear-host
            header
            write-output "In order to run the Active Directory Module, you must Specify the IP of the Domain Controller."
            write-output "If you don't need to run the Active Directory Module, you can skip this."
            write-output " "
            Write-output "1. Continue"
            write-output "2. Skip"
            $choice= read-host -Prompt " "
            clear-host

            if ($choice -eq "2"){
                write-output "Skipping Active Directory"
                start-sleep -Seconds 1
                new-variable -name activedirectoryconfiguration -Value "1" -Scope global -ErrorAction SilentlyContinue
                clear-host
            }

            if ($choice -ne "1" -and $choice -ne "2"){
                write-output "Invalid choice"
                start-sleep -Seconds 1
                Import-ActiveDirectory
            }

            if ($choice -eq "1"){
                header
                write-output "Please Enter the IP of the Domain Controller"
                new-variable -name domaincontrollerip -value $(read-host -prompt " ") -scope global -force -ErrorAction SilentlyContinue
                clear-host    
                    
                header
                Write-output "You'll need to provide the credentials to the Domain Controller."
                Write-output "1. Continue"
                write-output "2. Skip"
                $choice= read-host -Prompt " "
                clear-host
        
            
                if ($choice -ne "1" -and $choice -ne "2"){
                    write-output "Invalid choice"
                    Start-Sleep -Seconds 2
                    Import-ActiveDirectory
                }

                if ($choice -eq "2"){
                    clear-host
                    write-output "Skipping Active Directory"
                    new-variable -name activedirectoryconfiguration -Value "1" -Scope global -ErrorAction SilentlyContinue
                    start-sleep -Seconds 1
                }

                if ($choice -eq "1"){
                    new-variable -name DCcreds -Value $(get-credential) -Scope global -force -ErrorAction SilentlyContinue
                    $option = New-PSSessionOption -nomachineprofile
                    $dcsesh= New-PSSession -name dcsesh -ComputerName $domaincontrollerip -Credential $DCcreds -SessionOption $option
    
                    if (!$dcsesh){
                        clear-host
                        Write-Output "Authentication failed. Please try again."
                        sleep 2
                        Import-ActiveDirectory
                    } 

                    if ($dcsesh){
                        $ad= get-module | where {$_.name -like "*activedirectory*" -and $_.rootmodule -like "*activedirectory*"}
                        if ($ad){
                            clear-host
                            write-output "Active Directory module already loaded."
                            start-sleep -Seconds 1
                        }
    
                        if (!$ad){
                            clear-host
                            Write-output "Loading Active Directory module."
                            start-sleep -Seconds 1
                            Import-Module -PSSession $dcsesh -name activedirectory
                            $ad= get-module | where {$_.name -like "*activedirectory*" -and $_.rootmodule -like "*activedirectory*"}
                        }

                        Remove-PSSession -name dcsesh
                    }

                    if ($ad){
                        clear-host                    
                        write-output "Successfully imported the Active Directory Module."
                        new-variable -name activedirectoryconfiguration -Value "1" -Scope global -ErrorAction SilentlyContinue
                        sleep 2
                    }

                    if (!$ad){
                        clear-host
                        header
                        Write-Host "[ERROR]" -ForegroundColor Red
                        write-output "Active Directory import failed. Connection to remote server was successful though."
                        write-output " "
                        write-output "-Please try again, and be sure that the IP and Credentials you provide are indeed for a Domain Controller and not just a regular workstation."
                        write-output " "
                        pause
                        Import-ActiveDirectory
                    }
                }
            }
        }
    }
    #determines where to store the results
    function promptfor-Loglocal{
        clear-host
        header
        write-output "Please choose the location where you'd like the results to be stored."
        write-output " "
        Write-Output "1.) Locally on this computer (Pros: Able to post-process data | Cons: Might not scale well if querying over ~150 remote endpoints)"
        Write-Output "2.) Log the results as an event log on each remote endpoint. (Pros: quickly forward those events to a SIEM | Cons: Post-processing will not be available)"
        write-output "3.) Both."
        Write-Output " "
        $choice= Read-Host -prompt " "
        
        if ($choice -ne 1 -and $choice -ne 2 -and $choice -ne 3){
            clear-host
            write-output "Invalid selection"
            sleep 1
            clear-host
            promptfor-loglocal
        }

        if ($choice -eq 1){
            new-variable -name loglocal -value 1 -Scope global -Force -ErrorAction SilentlyContinue
        }

        if ($choice -eq 2){
            new-variable -name loglocal -value 2 -Scope global -Force -ErrorAction SilentlyContinue
        }

        if ($choice -eq 3){
            new-variable -name loglocal -value 3 -Scope global -Force -ErrorAction SilentlyContinue
        }

    }

    #sets up Splunk 
    function PromptFor-Splunk{
        if ($splunkconfiguration -eq "1" -or !$splunkconfiguration){
            function InstallSplunkForwarder{
                $splunk= $(Get-ChildItem $env:USERPROFILE\Desktop\TheGreaterWall\Source\ | where {$_.name -like "*splunk*" -and $_.name -like "*forwarder*"} -ErrorAction SilentlyContinue)              
            
                if ($splunk){
                    clear-host
                    header
                    Write-Output "Enter the IP and port of your splunk server (ex: 127.0.0.1:9997)"
                    $serverlocation= Read-Host -Prompt " "
                    $x= 0
                    
                    while ($x -lt 2){
                        clear-host
                        header
                        
                        if ($x -eq 0){
                            $action= "Create a"
                        }
                        
                        if ($x -eq 1){
                            $action= "Retype the"
                        }
                            
                        write-output "$action password for the Splunk Forwarder"
                        new-variable -name "pass$x" -Value $(Read-Host -Prompt " ") -Force -ErrorAction SilentlyContinue
                        $x++
                    }
            
                    $diff= Compare-Object $pass0 $pass1
            
                    if ($diff){
                        clear-host
                        write-output "Passwords do not match."
                        sleep 2
                        InstallSplunkForwarder
                    }
            
                    if (!$diff){
                        $splunk_forwarder= $(Get-ChildItem $env:USERPROFILE\Desktop\TheGreaterWall\source | where {$_.name -like "*splunk*" -and $_.name -like "*forwarder*"}).fullname
                        #msiexec.exe /i $splunk_forwarder RECEIVING_INDEXER="$serverlocation" SPLUNKPASSWORD=password AGREETOLICENSE=Yes /quiet
                        msiexec.exe /i $splunk_forwarder
                    }
                } 
                                
                if (!$splunk){
                    clear-host
                    #header
                    Write-Host "[Error]" -ForegroundColor red
                    Write-Output "No splunk Forwarder Detected in $env:USERPROFILE\Desktop\TheGreaterWall\Source\"
                    Write-Output "You must provide the Splunk forwarder. It is not included in the default zip download for The Greater Wall."
                    write-output " "
                    pause                    
                }     
            }
    
            clear-host
            header
            Write-Output "The Greater Wall can Forward logs to a local or remote splunk server"
            write-output " "
            write-output "1.) Configure forwarding to local Splunk instance"
            Write-Output "2.) Configure Forwarding to remote Splunk server"
            Write-Output "3.) Skip Splunk Configuration"
            $splunkchoice= Read-Host -Prompt " "
            
            if ($splunkchoice -eq "2"){
                InstallSplunkForwarder
                new-variable -name Logaggregatorchoice -value "SplunkForwarder" -Scope global -ErrorAction SilentlyContinue
            }
            
            if ($splunkchoice -eq "1"){
                $splunkservice= get-service -name Splunkd | where {$_.status -eq "Running"}
                $splunkweb= Invoke-WebRequest -uri "http://127.0.0.1:8000/en-US/app/launcher/home"
                new-variable -name Logaggregatorchoice -value "Splunkd" -Scope global -ErrorAction SilentlyContinue
                
                if ($splunkweb.StatusCode -eq 200 -and $splunkservice){
                    clear-host
                    header
                    Write-host "[Success]" -ForegroundColor Green
                    Write-Output "Splunkd service is running"
                    Write-host "[Success]" -ForegroundColor Green
                    Write-Output "The Greater Wall detected Splunk Web hosted at 127.0.0.1:8000"
                    Write-Output " "
                    Write-Output "Make sure to Configure the settings from the splunk web page:"
                    Write-Output "    -Settings->Data Inputs->Local Event Log Collection | Choose 'TGW' in the available logs menu."
                    write-output " "
                    pause
                }
        
                if (!$splunkservice){
                    clear-host
                    header
                    Write-host "[Error]" -ForegroundColor Red
                    Write-Output "Splunk service not detected or not running"
                }
                                
                if ($splunkweb.StatusCode -ne "200"){
                    clear-host
                    header
                    Write-host "[Error]" -ForegroundColor Red
                    Write-Output "Splunk web not detected"
                    Write-Output "Please ensure that you install Splunk Enterprise, free or otherwise."
                    Write-Output "The splunk binaries are not included in the default zip file for The Greater Wall"
                    Write-Output " "
                    pause
                }
            }
    
            if ($splunkchoice -eq "3"){
                clear-host
                header
                Write-Output "Skipping Splunk setup"
                sleep 2
                clear-host
            }
        }
        New-Variable -name splunkconfiguration -value "0" -Force -scope global -ErrorAction SilentlyContinue
    }   
        
        #Uninstalls Splunk Forwarder
    function UninstallSplunkForwarder{
        $service= Get-WmiObject win32_service | where {$_.name -like "*splunk*" -and $_.name -like "*forwarder*"}
        $splunk_forwarder= $(Get-ChildItem $env:USERPROFILE\Desktop\TheGreaterWall\source | where {$_.name -like "*splunk*" -and $_.name -like "*forwarder*"}).fullname
    
        if (!$service){
            clear-host 
            header
            Write-Output "-No splunk Service Detected"
        }
        
        if (!$splunk_forwarder){
            clear-host
            header
            Write-Output "No Splunk.exe detected"
        }
    
        try{
            if ($service){
                $service.StopService()
                Start-Sleep -s 1
                $service.delete()           
            }
        }
        catch{
            $splunk_home= 'C:\Program Files\SplunkUniversalForwarder\bin'
            "$splunkhome\splunk.exe stop"
        }

        msiexec.exe /x $splunk_forwarder
    }

    #Sets up winlogbeat forwarder parameters
    function Setup-TGW_Logbeat{
        if ($tgw_logbeatconfiguration -eq "0" -or !$tgw_logbeatconfiguration){
            clear-host
            header
            write-output "The Greater Wall has the ability to forward it's results to Security Onion VIA Winlogbeat."
            write-output "If you don't wish to use this feature, you can skip this."
            write-output " "
            Write-output "1. Continue with Winlogbeat setup"
            write-output "2. Skip"
            $choice= read-host -Prompt " "
            clear-host

            if ($choice -eq "2"){
                write-output "Skipping Winlogbeat setup."
                start-sleep -Seconds 1
                new-variable -name tgw_logbeatconfiguration -Value "1" -Scope global -ErrorAction SilentlyContinue
                clear-host
            }

            if ($choice -ne "1" -and $choice -ne "2"){
                write-output "Invalid choice"
                start-sleep -Seconds 1
                Setup-TGW_Logbeat
            }

            if ($choice -eq "1"){
                header
                write-output "Please Enter the IP and port of your Security Onion in the following format- IP:Port"
                write-output "-Example - 10.0.0.150:5044"
                $securityonionip= read-host -Prompt " "
                $securityonionip= $securityonionip.TrimStart('"').trimend('"')
                new-variable -name securityonionip -value $securityonionip -scope global -force -ErrorAction SilentlyContinue
                clear-host
                header
                write-host "Security onion IP and port configured as -- $securityonionip --."     
                write-output " "                                 
                new-variable -name tgw_logbeatconfiguration -value 1 -scope global  
                new-variable -name LogAggregatorChoice -value "TGWLB" -Scope global -ErrorAction SilentlyContinue
                pause
                clear-host                          

                $configfile= get-content $env:userprofile\Desktop\TheGreaterWall\Source\TGW_Logbeat.yml
                $hostentry= $($configfile | select-string "hosts: \[").tostring()
                $oldval= $hostentry.split('[').split(']')[-2]-replace('"','')
                new-item -itemtype Directory -path C:\Windows\Temp\ -name TGWLB -erroraction silentlycontinue
                $configfile-replace("$oldval","$securityonionip") >$env:userprofile\Desktop\TheGreaterWall\Source\TGW_Logbeat.yml
                $(get-content $env:userprofile\Desktop\TheGreaterWall\Source\TGW_Logbeat.yml) >C:\windows\temp\TGWLB\TGW_Logbeat.yml

                $winlogbeatbinary= @()
                $winlogbeatbinary+= $(Get-ChildItem $env:userprofile\desktop\TheGreaterWall\Source\ | where {$_.extension -eq ".exe"}).fullname
                $winlogbeatbinary+= "None of these"

                $winlogbeatbinary= $winlogbeatbinary | Out-GridView -PassThru -Title "Choose WinLogbeat Executable"

                if ($winlogbeatbinary -eq "None of these"){
                    clear-host
                    header
                    write-host "[ERROR/WARNING]" -ForegroundColor DarkYellow
                    Write-output "You must place the Winlogbeat executable at path: $env:userprofile\Desktop\TheGreaterWall\Source\"
                    Write-Output " "
                    write-output "  -In order to maintain the claim that The Greater Wall is 100% written in PowerShell, Winlogbeat is not part of the default package."
                    Write-Output "  -You must download the file separately and ensure that you have obtained permission for the installation by the system owners."
                    write-output "  -It's preferred if you name the file 'seconionbeat.exe'"
                    write-output "  -If you name it something else, it will automatically be renamed to 'seconionbeat.exe' by The Greater Wall."
                    write-output "  -A copy is available at https://github.com/NintendoWii/TGW_Logbeat"
                    Write-Output " "
                    write-host "  -TLDR- missing file: $env:userprofile\desktop\TheGreaterWall\Source\seconionbeat.exe" -ForegroundColor Red
                    Write-Output ""
                    pause
                }

                if ($winlogbeatbinary -ne "None of these"){
                    new-item -ItemType Directory -Path C:\Windows\Temp\ -Name TGWLB -ErrorAction SilentlyContinue

                    remove-item -path C:\Windows\Temp\TGWLB\TGW_Logbeat.yml -ErrorAction SilentlyContinue
                    remove-item -path C:\Windows\Temp\TGWLB\seconionbeat.exe -ErrorAction SilentlyContinue

                    copy-item -Path $env:USERPROFILE\Desktop\TheGreaterWall\Source\TGW_Logbeat.yml -Destination C:\Windows\temp\TGWLB\ -ErrorAction SilentlyContinue
                    try{
                        Copy-Item -path $winlogbeatbinary -Destination C:\Windows\Temp\TGWLB\seconionbeat.exe -ErrorAction SilentlyContinue
                    }
                    Catch{}

                    sleep 1

                    # Delete and stop the service if it already exists.
                    if (Get-Service TGWLB -ErrorAction SilentlyContinue){
                        $service = Get-WmiObject -Class Win32_Service -Filter "name='TGWLB'"
                        $service.StopService()
                        Start-Sleep -s 1
                        $service.delete()
                    }
    
                    $workdir= $(pwd).tostring()

                    #Create initial Log that TGWLB will reconginize IOT begin connection attempts
                    New-EventLog -LogName TGW -Source TGW -ErrorAction SilentlyContinue
                    Limit-EventLog -LogName TGW -MaximumSize 4000000KB -ErrorAction SilentlyContinue
                    Write-EventLog -LogName TGW -Source TGW -EntryType Warning -EventId 115 -Message "TGW_Logbeat_Init"

                    # Create the new service.
                    New-Service -name tgwlb `
                        -displayName tgwlb `
                        -binaryPathName "`"C:\Windows\temp\TGWLB\seconionbeat.exe`" --environment=windows_service -c `"C:\Windows\temp\TGWLB\TGW_Logbeat.yml`" --path.home `"C:\Windows\temp\TGWLB`" --path.data `"$env:PROGRAMDATA\seconionbeat`" --path.logs `"$env:PROGRAMDATA\winlogbeat\logs`" -E logging.files.redirect_stderr=true"

                    # Attempt to set the service to delayed start using sc config.
                    Try {
                    Start-Process -FilePath sc.exe -ArgumentList 'config tgwlb start= delayed-auto'
                    }

                    Catch { Write-Host -f red "An error occured setting the service to delayed start." }    
            
                    "sc start tgwlb" | cmd        
                    Start-Sleep -Seconds 2
                    clear-host

                    $tgwlb_service= get-service -name tgwlb -ErrorAction SilentlyContinue

                    #Check to make sure the service is running and display error if it isn't
                    if ($tgwlb_service.status -ne "Running"){
                        clear-host
                        header
                        write-host "[ERROR] Unable to start TGW_Logbeat (TGWLB) Service" -ForegroundColor Red
                        write-host " "
                        Write-Output "  -Try double checking the executable you specified and make sure it's correct."
                        write-output "  -Make sure the executable file isn't corrupted."
                        Write-Output "  -Make sure the TGW_Logbeat.yml file is correct."
                        write-output " "
                        pause
                    }
            
                    if ($tgwlb_service.status -eq "Running"){
                        #Check to make sure the network connection is good between TGW and Security Onion Node
                        $Config= $(Get-Content C:\Windows\Temp\TGWLB\TGW_Logbeat.yml | select-string "Hosts: ").tostring().split(':')-replace('\["','')-replace('"]','')
                        $Config= $($Config | % {$_.TrimStart().trimend()})[1..2]
                        $port= $config[1]
                        $ip= $Config[0]
                        clear-host
                        Write-Output "Checking Network Connection to Security Onion Node specified in C:\Windows\Temp\TGW_Logbeat.yml"
                        Write-Output "This can anywhere from 1 to 30 Seconds...Please be patient."
                
                        #$netconnection= Get-NetTCPConnection | where {$_.RemoteAddress -eq "$ip" -and $_.RemotePort -eq "$port"}

                        if (!$netconnection){
                            $x= 0
                            $y= 0
                            while ($true -and $y -eq "0"){
                                sleep 2                        
                                $netconnection= Get-NetTCPConnection | where {$_.RemoteAddress -eq "$ip" -and $_.RemotePort -eq "$port"}
                                $netconnection >> $env:userprofile\Desktop\TheGreaterWall\TGWLogs\Netconnectionlog.txt

                                if ($netconnection.localaddress){
                                    sleep 2
                                    $netconnection= Get-NetTCPConnection | where {$_.RemoteAddress -eq "$ip" -and $_.RemotePort -eq "$port"}
                                    $netconnection >> $env:userprofile\Desktop\TheGreaterWall\TGWLogs\Netconnectionlog.txt

                                    if ($netconnection.state -eq "Established"){
                                        clear-host
                                        header
                                        write-host "[Success] TGW_Logbeat is running and is communicating with Security Onion Node specified in C:\Windows\Temp\TGW_Logbeat.yml"
                                        sleep 2
                                        $y= 1
                                    }

                                    if ($netconnection.state -ne "Established"){
                                        clear-host
                                        header
                                        write-host "[ERROR] Trouble communicating to Security Onion Node" -ForegroundColor Red
                                        Write-Output " "
                                        Get-Content $env:userprofile\Desktop\TheGreaterWall\TgwLogs\Netconnectionlog.txt
                                        Write-Output " "
                                        Write-Output "  -TIP #1: Check Host Firewall and all network firewalls between this host and the Security Onion Node for rules that block port: ($port) traffic."
                                        write-output "  -TIP #2: If the status is [SynSent] the most common issue is that a route needs to be added on Security Onion Node that tells it how to reach this host"
                                        write-output "  -TIP #3: Ensure that you run Sudo-so-allow pn the Security Onion node in order to allow tcp:$port traffic."
                                        Write-output "  -TIP #4: It's advised to use the standard port of 5044 in C:\windows\temp\TGW_Logbeat.yml because that's the default for Security Onion. Your's is set to $port."
                                        write-output " " 
                                        pause
                                        remove-item -Path $env:userprofile\Desktop\TheGreaterWall\TGWLogs\Netconnectionlog.txt -Force -ErrorAction SilentlyContinue
                                        break
                                    }
                                }                            
        
                                if (!$netconnection){
                                    $x++                        
                                    if ($x -eq 10){
                                        clear-host
                                        header
                                        write-host "[ERROR] Unable to communicate to Security Onion Node" -ForegroundColor Red
                                        Write-Output " "
                                        Write-Output " No connection attempts seen. It's likely a host machine issue rather than a networking issue. Check firewall/policy/routing table."
                                        Write-Output " "
                                        pause
                                        break
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Function Uninstall-TGWLogBeat{
        clear-host
        $service = Get-WmiObject -Class Win32_Service -Filter "name='tgwlb'"

        if ($service){
            $service.StopService()
            Start-Sleep -s 1
            $service.delete()
            Remove-Item -Path C:\windows\temp\TGWLB -Force -Recurse -ErrorAction SilentlyContinue
            clear-host
            header
            Write-output "TGW_Logbeat service has been stopped and deleted and the TGWLB directory has been removed from C:\windows\temp"
            write-output " "
            pause
            clear-host
        }

        if (!$service){
            clear-host
            header
            write-output "TGW_Logbeat service not found. Nothing to stop, no files deleted"
            write-output " "
            pause
            clear-host
        }
    }   

    #Tests the WINRM connectivity to the target IPs
    function get-wsmanconnection ($listofips){
        if ($completedconnectiontest -ne "Yes"){
            clear-host
            header
            Write-Output "           *****Connection Test*****`n"
            write-output "1.) Test the connectivity of your ($($listofips.count)) IP(s)."
            Write-Output "2.) Test the connectivity of a Single IP."
            write-output "3.) Do not run Connection test. (advised)"
            $choice= Read-Host -Prompt " "
            
            if ($choice -ne "2" -and $choice -ne "1" -and $choice -ne "3"){
                clear-host
                write-output "Invalid Selection."
                sleep 1
                get-wsmanconnection $listofips
            }

            if ($choice -eq "3"){
                new-variable -name completedconnectiontest -value "Yes" -Force -ErrorAction SilentlyContinue -Scope global
            }

            if ($choice -eq "2"){
                clear-host
                write-output "Enter the IP address."
                $ip= read-host -prompt " "
                $regex= "^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])(\.(?!$)|$)){4}$"
                
                if ($ip | select-string -NotMatch -Pattern $regex){
                    clear-host
                    write-output "Invalid IP"
                    sleep 2
                    get-wsmanconnection $listofips
                }
                
                else{
                    #Do Nothing
                }      
            }

            if ($choice -eq "1" -or $choice -eq "2"){
                new-variable -name completedconnectiontest -value "Yes" -Force -ErrorAction SilentlyContinue -Scope global
                get-job | remove-job -Force -ErrorAction SilentlyContinue
                
                Function Test-ComputerConnection{
                    [CmdletBinding()]
                    param
                    (
                    [Parameter(Mandatory=$True,
                    ValueFromPipeline=$True, ValueFromPipelinebyPropertyName=$true)]
                    [alias("CN","MachineName","Device Name")]
                    [string]$ComputerName   
                    )
                    Begin{
                        [int]$timeout = 20
                        [switch]$resolve = $true
                        [int]$TTL = 128
                        [switch]$DontFragment = $false
                        [int]$buffersize = 32
                        $options = new-object system.net.networkinformation.pingoptions
                        $options.TTL = $TTL
                        $options.DontFragment = $DontFragment
                        $buffer=([system.text.encoding]::ASCII).getbytes("a"*$buffersize)   
                    }
                    Process{
                        $ping = new-object system.net.networkinformation.ping
                       
                        try{
                            $reply = $ping.Send($ComputerName,$timeout,$buffer,$options)    
                        }

                        catch{
                            $ErrorMessage = $_.Exception.Message
                        }
                        
                        if ($reply.status -eq "Success"){
                            $props = @{ComputerName=$ComputerName
                            Ping="Success"
                            WinRM=""
                        }
                    }
              
                    else{
                        $props = @{ComputerName=$ComputerName
                        Ping="Failed"  
                        Winrm=""         
                    }
                }
                New-Object -TypeName PSObject -Property $props
            }
            End{}
        }

                $status= @()      

                if ($choice -eq "2"){
                    Write-output "Conducting quick ping scan"
                    write-output "(1 / 1)"
                    $status+= Test-ComputerConnection $ip
                    clear-host
                    Write-Output "Finished ping test."
                    sleep 2
                    clear-host
                    write-output "Conducting WINRM Connection Test"
                    $wsman= test-wsman -ComputerName $ip  -ErrorAction SilentlyContinue | Out-Null
                    
                    if ($($wsman | select-string "xsd")){
                                $($status).WinRM="Success"
                            }
                 
                    if (!$wsman){
                        $($status).WinRM="Failed"
                    }
                
                }

                if ($choice -eq "1"){
                    $ips= $listofips        
                    clear-host                
                    $x= 0
        
                    foreach ($i in $Ips){
                        clear-host
                        Write-output "Conducting quick ping scan"
                        write-output "($x / $($ips.count))"
                        $status+= Test-ComputerConnection $i
                        $x++
                    }
            
                    $z= 0
                    $y= 0
                    clear-host
                    Write-Output "Finished ping test."
                    sleep 2
                    clear-host
                    write-output "Conducting WINRM Connection Test"
                    
                    while ($z -lt $ips.count){
                        clear-host
                        $x= 0
                    
                        if ($z -lt $ips.count){
                            while ($x -le 10 -and $z -le $ips.count){
                                if ($ips[$y]){
                                    $computername= $ips[$y]
                                    start-job -ScriptBlock {$computername= $args[0];test-wsman -ComputerName $computername} -Name $computername -ArgumentList $computername
                                    clear-host
                                    Write-output "Conducting WinRM Scan."
                                }
                         
                                $x++
                                $y++
                                $z++
                                
                            }
                            
                            sleep 5
                    
                            $jobs= get-job
                  
                            foreach ($j in $jobs){
                                clear-host
                                write-output "Conducting WinRM Scan."
                                    
                                if ($j.state -eq "Completed"){
                                    clear-host
                                    if (!$($j | Receive-Job -keep -verbose | select-string "WSMANFault") -or $($j | Receive-Job -keep -verbose | select-string "xsd")){
                                        $($status | where {$_.computername -eq $($j.name)}).WinRM="Success"
                                    }
                 
                                    if (!$($j | Receive-Job -keep -Verbose) -or $($j | Receive-Job -keep -Verbose | select-string "WSMANFault")){
                                        $($status | where {$_.computername -eq $($j.name)}).WinRM="Failed"
                                    }
                                }
                    
                                if ($j.state -ne "completed"){
                                    $j | stop-job
                                    $($status | where {$_.computername -eq $($j.name)}).WinRM="Failed"
                                }
                 
                                $j | remove-job -force                                points
                            }
                        }                
                    }
                }
                                
                $unreachable= $status | where {$_.winrm -eq "Failed"}
                
                if ($unreachable){
                    clear-host
                    write-output "Warning. The following endpoints are unreachable. No modules will be attempted on these endpoints."
                    $unreachable | format-table
                    write-output " "
                    pause
                    foreach ($u in $unreachable){
                        $listofips= $listofips | where {$_ -ne $u.computername}
                        New-Variable -name listofips -Value $listofips -Force -ErrorAction SilentlyContinue -Scope global
                    }
                }
    
                else{
                    sleep 2
                    clear-host
                    header
                    Write-Output "All Endpoints are reachable.`n"
                    pause
                }
                
                new-variable -name connectionstatus -value $($status) -Force -ErrorAction SilentlyContinue -Scope global
                $date= (Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join "" 
                if($connectionstatus){
                    $connectionstatus | convertto-csv | where {$_ -notlike "*#TYPE System.Management.Automation.PSCustomObject*"} >$env:userprofile\desktop\thegreaterwall\TgwLogs\ConnectionStatus$date.txt
                }                                      
            }
        }
    }

    #Compresses all the results into an archive to be saved or viewed later and ensures that they dont get re-postprocessed
    function archive-results{
    $date= (Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join ""
    new-item -path $env:USERPROFILE\desktop\thegreaterwall\results -name "Archived_results" -ErrorAction SilentlyContinue -ItemType directory
    new-item -path $env:USERPROFILE\desktop\thegreaterwall\results\Archived_results -name Archived_$date -ErrorAction SilentlyContinue -ItemType Directory

    $items= Get-ChildItem $env:USERPROFILE\desktop\thegreaterwall\results | where {$_.name -ne "Dropbox" -and $_.name -notlike "*postprocess*" -and $_.name -ne "Archived_results"}

    foreach ($i in $items){
        $path= $i.FullName
        $name= $i.name
        Move-item $path -Destination "$env:userprofile\Desktop\TheGreaterWall\results\archived_results\Archived_$date\$name"
    }
}

    #Runs the post processor 
    function postprocessor{
        $results= $(Get-ChildItem $env:userprofile\desktop\thegreaterwall\results | where {$_.name -notlike "*dropbox*"} | where {$_.name -notlike "*postprocess*"} | where {$_.name -notlike "*ActiveDirectoryEnumeration*"} | where {$_.name -notlike "*archive*"}).count

        #add Datasets and make them global
        #If there is a configuration for a dataset in modules.conf, the post processor will be aware of them
        $datasets= @()
        $datasets+= $(get-content $env:userprofile\Desktop\TheGreaterWall\Modules\Modules.conf | convertfrom-csv -Delimiter :).p1 | sort -Unique
        New-Variable -name datasets -Value $datasets -Scope global -force -ErrorAction SilentlyContinue

        Set-Location $env:USERPROFILE\desktop\thegreaterwall\results
    
        function setup-workingenvironment{
            #Sets up post processing environment
            #3 global variables created
            #$resultspath
            #$foldernames
            #$postprocessingpath
            #New-Variable -name resultspath -Value "$env:userprofile\desktop\TheGreaterWall\Results" -scope global -Force
            New-Variable -name date -Value $((Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join "") -force -ErrorAction SilentlyContinue    
            $choice= $($(Get-ChildItem $env:userprofile\desktop\TheGreaterWall\ | where {$_.name -like "*results*"}).FullName) | Out-GridView -Title "Choose Results folder to work with" -PassThru
            New-Variable -name resultspath -value $choice -Scope global -Force
            set-location $resultspath
            new-item -Path $resultspath -ItemType Directory -name "PostProcessing_$date"
            
            #this folder will be reserved for when winlogbeat support is developed
            #new-item -Path $resultspath -ItemType Directory -name "Dropbox" -ErrorAction SilentlyContinue
        
            #find old postprocessed folder
            $oldfolders= $(Get-ChildItem $resultspath | where {$_.name -like "*postprocess*"})
            $folders= @()
            $folders+= "Folder,Status"
        
            foreach ($o in $oldfolders){
                $foldercontents= Get-ChildItem $o -Force -Recurse
                $postprocessed= $foldercontents | where {$_.name -like "*postprocessed"}
                $enriched= $foldercontents | where {$_.name -eq "RawData"}
                $analyed= $foldercontents | where {$_.name -eq "OutlyerAnalysis"}
        
                $date= get-date
                $age= $(New-TimeSpan -Start $($o.lastwritetime) -end $date).totalseconds
        
                if ($postprocessed -and $enriched -and $analyed){
                    $folders+= "$($o.fullname),Already post-processed and analyzed"
                }
        
                if ($postprocessed -and $enriched -and -not $analyed){
                    $folders+= "$($o.fullname),Post-processed and enriched. Not analyzed"
                }
        
                if ($postprocessed -and -not $enriched -and -not $analyed){
                    $folders+= "$($o.fullname),Post-processed but not enriched or analyzed"
                }
        
                if (!$postprocessed -and $age -gt 5){
                    Remove-Item $o -Force -ErrorAction SilentlyContinue
                }
        
                if (!$postprocessed -and $age -le 10){
                    $folders+= "$($o.fullname),Empty  *NEW!*"
                }
            }
    
            $folders= $folders | convertfrom-csv
            $folders= $folders | sort -Descending -Property status
            $choice= $folders | Out-GridView -Title "Choose Post Processing folder to work with" -PassThru
            $choice= $choice.folder
            New-Variable -name postprocessingpath -value $choice -Scope global -Force
            $postprocessingpath        
        
            #Make folders in the working directory that correspond to each endpoint
            New-Variable -name foldernames -value $(Get-ChildItem $resultspath | where {$_.fullname -notlike "*PostProcessing_*"} | where {$_.name -ne "Dropbox"}) -scope global -Force
                
            foreach ($f in $foldernames.name){
                new-item -Path $postprocessingpath -Name "$f-PostProcessed" -ItemType Directory
                
            }
        }
        
        function setup-analysisenvironment{
            Set-Location $postprocessingpath
            new-item -Path $postprocessingpath -name AnalysisResults -ItemType Directory -ErrorAction SilentlyContinue
            New-Variable -name postprocessfoldernames -Value $(Get-ChildItem -Path $postprocessingpath | where {$_.name -like "*postprocessed*"} | where {$_.name -notlike "*ActiveDirectory*"}) -Force -Scope global
            new-item -Path $postprocessingpath -name RawData -ItemType directory
        }

        function CopyTo-Raw{
            Remove-Variable -name name -Force -ErrorAction SilentlyContinue
            Remove-Variable -name file -Force -ErrorAction SilentlyContinue
            $ErrorActionPreference= "SilentlyContinue"
           
            #copy active directory file. This just needs to happen one time; not once for each folder.
            $adfolderpostprocess= Get-ChildItem -Path $postprocessingpath -ErrorAction SilentlyContinue | where {$_.name -like "*postprocessed_nh*"} | where {$_.name -like "*ActiveDirectory*"}
            
            if ($adfolderpostprocess){
                $adname= $($adfolderpostprocess.name.tostring().split('-'))[0]
                $adfolder= $adfolderpostprocess.FullName
                $targetfile= $(Get-ChildItem -Recurse -path $adfolder -ErrorAction SilentlyContinue | where {$_.name -like "*activedirectory*" -and $_.name -like "*_nh*" -and $_.attributes -eq "Archive"}).fullname
            
                if ($targetfile){
                    $content= get-content $targetfile
                    $content >> "$postprocessingpath\RawData\all_ActiveDirectoryEnumeration.csv"
                }
        
                if (!$targetfile){
                    Write-host "[Warning] $dataset file missing for $name" -ForegroundColor Red
                }
            }

            #Copy all the rest of the files
            foreach ($folder in $postprocessfoldernames){
                $name= $($folder.name.tostring().split('-'))[0]
                $folder= $folder.FullName
        
                foreach ($dataset in $datasets){
                    $targetfile= $(Get-ChildItem -path $folder -ErrorAction SilentlyContinue | where {$_.name -like "*$dataset*" -and $_.name -like "*_nh*"}).fullname

                    if ($targetfile){
                        $content= get-content $targetfile
                        $content >> "$postprocessingpath\RawData\all_$dataset.csv"
                    }
        
                    if (!$targetfile){
                        Write-host "[Warning] $dataset file missing for $name" -ForegroundColor Red
                    }
                }
            }
        }

        function cleanup-headers{
            #clean up the headers
            write-output "Re-applying headers"
            $path= "$postprocessingpath\RawData"
            $files= Get-ChildItem $path

            $configuration= get-content $env:userprofile\Desktop\thegreaterwall\modules\modules.conf | convertfrom-csv -Delimiter :

            foreach ($file  in $files){
                $fullname= $file.fullname
                $filename= $file-replace('all_','')-replace('.csv','')          
                $conf= $configuration | Where {$_.p1 -eq $filename}
                $header= $($conf | where {$_.p2 -eq "csvheader"}).p3.tostring()
                $alt_header= $header-replace(',','","')
                $alt_header= '"' + $alt_header + '"'
            
                #reapply headers to postprocessed datasets
                if ($header -ne 'LEAVE-ORIGINAL'){                    
                        
                    if ($conf){
                        $content= get-content $fullname | where {$_ -ne $header -and $_ -ne $alt_header}
                        $output= @()
                        $output+= $header
                        $output+= $content
                        $output >$fullname
                    }
                }
            }
            write-output "Done re-applying headers"
        }

        function calculate-time($start,$end){
            $t= New-TimeSpan -Start $start -End $end
            $seconds= $t.Seconds
            $minutes= $t.minutes
            
            if ($seconds -ge 1 -and $minutes -eq 0){
                $seconds= "$seconds" + "s"
            }
        
            if ($seconds -eq 0 -and $minutes -eq 0){
                $seconds= $t.Milliseconds
                $seconds= "$seconds" + "ms"
            }
        
            if ($minutes -ge 1){
                $seconds= "$minutes" + "m" + " $seconds" + "s"
            }
            return $seconds
        }

        function ExtractCSVFrom-PowerShellLogs{
            $Logs= $(Get-ChildItem -Recurse $env:USERPROFILE\Desktop\TheGreaterWall\Results -Depth 1 | where {$_.name -notlike "*postprocess*"} | where {$_.name -notlike "*archive*"}| where {$_.name -like "*powershell*"})
            try{
                $analystname= whoami
                $analystsid= $(whoami /all | Select-String $analysytname -SimpleMatch).tostring().split(" ")[1]
            }
            catch{
                $analystsid= $(Get-WmiObject win32_useraccount | where {$_.name -eq "$env:Username"}).sid.tostring()
            }
                
            #For debugging purposes, uncomment the next line
            #$analystsid= 0
            

            foreach ($l in $logs){
                $log= get-content $l.fullname
                $ip= $l.Directory.name.tostring()
                $csvstart= $($($log | select-string "START CSV").LineNumber)[-1]
                $csvend= $($($log | select-string "END CSV").LineNumber)[-1] -1
            
                $csvoutput= $log[$csvstart..$($csvend - 1)]
                $csvoutput= $csvoutput | ConvertFrom-Csv | where {$_.userSID -ne $analystsid}
                
                foreach ($c in $csvoutput){
                    $c.ip = $ip
                }

                $csvoutput= $csvoutput | convertto-csv -NoTypeInformation
                $outputpath= "$postprocessingpath" + "\" + "$($l.Directory.name.tostring())-PostProcessed" + "\" + "PowerShellLogs-postprocessed.csv" 
                $outputpath_nh= "$postprocessingpath" + "\" + "$($l.Directory.name.tostring())-PostProcessed" + "\" + "PowerShellLogs-postprocessed_nh.csv"                
                $csvoutput >$outputpath
                $csvoutput[1..$($csvoutput.Count)] >$outputpath_nh
            }
        }

        function cleanpowershell-logs{
            $Logs= $(Get-ChildItem -Recurse $env:USERPROFILE\Desktop\TheGreaterWall\Results -Depth 1 | where {$_.name -notlike "*postprocess*"} | where {$_.name -notlike "*archive*"}| where {$_.name -like "*powershell*"}).fullname
            
            try{
                $analystname= whoami
                $analystsid= $(whoami /all | Select-String $analysytname -SimpleMatch).tostring().split(" ")[1]
            }
            catch{
                $analystsid= $(Get-WmiObject win32_useraccount | where {$_.name -eq "$env:Username"}).sid.tostring()
            }

            #For debugging purposes, uncomment the next line
            #$analystsid= 0


            foreach ($l in $logs){
                $log= get-content $l
                $csvstart= $($($log | select-string "START CSV").LineNumber)[-1]
                $csvend= $($($log | select-string "END CSV").LineNumber)[-1] -1
                $messages= $log[0..$($csvstart - 1)]
            
                $csvoutput= $log[$csvstart..$($csvend - 1)]
                $csvoutput= $csvoutput | ConvertFrom-Csv
            
                $messageobj=@()
                $messageobj+= "messagehash,RecordID,Start,End"
               
                $indexes= $($messages | select-string "TGWindex=" | where {$_ -notlike "*Write-output*"} | where {$_ -notlike "*$*"} | select line,linenumber)
                $messagehashes= $($messages | select-string "messagehash=" | where {$_ -notlike "*Write-output*"}  | where {$_ -notlike "*$*"} | select line,linenumber)
                $recordids= $($messages | select-string "recordid=" | where {$_ -notlike "*Write-output*"} | where {$_ -notlike "*$*"} | select line,linenumber)
                $indexcount= $indexes.count - 1        
        
                #Construct metadata object for the message field
                $x= 0
            
                while ($x -lt $indexcount){
                    $gh= $messagehashes[$x].line.tostring()-replace('messagehash= ','')
                    $recordid= $recordids[$x].line.tostring()-replace('Recordid= ','')
                    $start= $indexes[$x].linenumber.tostring()
                    $start= $start - 1
                    $end= $indexes[$($x + 1)].LineNumber.tostring()
                    $end= $end -2
                    $messageobj+= "$gh,$recordid,$start,$end"
                    $x++
                }
        
                $messageobj= $messageobj | convertfrom-csv | sort -Unique -Property messagehash
                
            
                new-item -ItemType directory -path $env:USERPROFILE\Desktop\TheGreaterWall\TgwLogs\ -Name PowerShell_Master_Reference -ErrorAction SilentlyContinue
                $newGH= $messageobj.messagehash        
                $existingGH= $(get-childitem $env:userprofile\desktop\TheGreaterWall\tgwlogs\powershell_master_reference -ErrorAction SilentlyContinue).name | % {$_-replace('.txt','')}
                $diff= $(Compare-Object $newgh $existingGH | where {$_.sideindicator -eq "<="}).inputobject
        
                $new= $diff.count
                $old= $existingGH.count
        
                #only process logs that arent present in datacollection and exlude any that originated from YOUR SID.
        
                $hitcount= 0
        
                foreach ($d in $diff){
                    $m= $messageobj | where {$_.messagehash -eq "$d"}
                    $csvrecord= $csvoutput | where {$_.recordid -eq $($m.RecordID)}
                    
                    if ($csvrecord.UserSID -ne $analystsid){
                        $hitcount++
                        $start= $m.Start
                        $end= $m.end
                        $logoutput= $Log[$start..$end]
                        $filename= $m.messagehash + ".txt"
                        $logoutput >$env:USERPROFILE\Desktop\TheGreaterWall\tgwlogs\Powershell_master_reference\$filename
                    }
                }
            }
            
            $logobj= @()
            $logobj+= "messagehash,ScriptblockID,Position,Total"

            foreach ($i in $(get-childitem $env:USERPROFILE\Desktop\TheGreaterWall\tgwlogs\Powershell_master_reference\ | where {$_.name -notlike "*.collection"})){
                $filename= $i.FullName
                $content= get-content $filename
                $multi_scriptblock= $content | select-string 'Creating Scriptblock text \('
                
                if ($multi_scriptblock){  
                    $multi_scriptblock= $multi_scriptblock-replace('"Creating Scriptblock text \(','')
                    $multi_scriptblock= $multi_scriptblock-replace('\):"','')
                    $multi_scriptblock= $multi_scriptblock-replace(' of ','&')
                    [int]$position= $multi_scriptblock.tostring().split('&')[0]
                    $total= $multi_scriptblock.tostring().split('&')[1]
                    $scriptblockid= $Content[3].tostring()
                        
                    if ($scriptblockid -notlike "ScriptblockID= *"){
                        $scriptblockid= $($content | select-string "ScriptblockID= ").tostring()
                    }
                    $scriptblockid= $scriptblockid-replace('ScriptblockID= "ScriptBlock ID: ','')
                    $scriptblockid= $scriptblockid-replace('"','')
    
                    $logobj+= "$filename,$scriptblockid,$position,$total"                    
                }
            }
            
            $logobj= $logobj | convertfrom-csv

            $uniquescriptblocks= $logobj.scriptblockid | sort -Unique

            foreach ($u in $uniquescriptblocks){
                $collection= $logobj | where {$_.scriptblockid -eq "$u"}
                $collection | % {$_.position = [int]$_.position}
                $collection= $collection | sort -Property position
                [int]$total= $collection.total | sort -Unique

                $output= @()
                        
                foreach ($i in $collection){ 
                    $filename= $i.messagehash                         
                    $output+= " " 
                    $output+= "***Scriptblock $($i.position) of $total***"
                    $output+= " "
                    $output+= $(get-content $filename)
                 } 

                foreach ($i in $collection){      
                    $filename= $i.messagehash                       
                    $outputfile= $filename + ".collection"
                    
                    if (!$(Test-Path $outputfile)){
                        $output >$outputfile
                    }
                }
            }

        }
    


    ################
    #Start Analysis#
    ################
        Function identify-ActiveDirectoryOutlyers{
            $start= get-date
            new-item -ItemType Directory -Path $postprocessingpath\AnalysisResults -name OutlyerAnalysis -ErrorAction SilentlyContinue | out-null
            remove-variable -Name refinedoutput -Force -ErrorAction SilentlyContinue
            remove-variable -name output -Force -ErrorAction SilentlyContinue
        
            if (!$moduleconfiguration){
                $moduleconfiguration= Get-Content $env:USERPROFILE\Desktop\TheGreaterWall\Modules\Modules.conf | Convertfrom-csv -Delimiter :
                New-Variable -name obj -Value $($moduleconfiguration) -Force -ErrorAction SilentlyContinue
            }
                    
            if ($moduleconfiguration){
                #parse File for selected data
                $settings= $obj | where {$_.p1 -eq "ActiveDirectoryEnumeration"}
                $sortproperties= $($settings | where {$_.p2 -eq "Pivot"}).p3                
        
                #get contents of file
                $path= "$postprocessingpath\RawData\all_activedirectoryEnumeration.csv"
                $output= get-content $path -ErrorAction SilentlyContinue
                                        
                if (!$output){
                    Write-Host "[Warning] no Active Directory file" -ForegroundColor Red
                }
                        
                if ($output){
                    $refinedoutput= $output | ConvertFrom-Csv
                            
                    foreach ($r in $refinedoutput){            
                        $r.groups = $r.groups-replace(',','|')
                        #pad NULL into places where the original collection script didnt
                        $needs_null= $($r | gm | where {$_.definition -like "*="}).name
        
                        foreach ($n in $needs_null){
                            $r.$n = "NULL"
                        }
                    }
        
                    $refinedoutput | Add-Member -NotePropertyName Propertyflagged -NotePropertyValue "NULL"
                    $refinedoutput | Add-Member -NotePropertyName Valueflagged -NotePropertyValue "NULL"
                    $refinedoutput | Add-Member -NotePropertyName FlagDescription -NotePropertyValue "NULL"
                    $accounts= $refinedoutput.samaccountname
        
                    #define number of useraccounts as half of the total count
                    $numberofuseraccounts= $($refinedoutput.samaccountname.count)/2
                                
                    #round up if decimal
                    if ($numberofuseraccounts.ToString() | select-string "\."){
                        $numberofuseraccounts= $($numberofuseraccounts.tostring().split("\."))[0]
                        $numberofuseraccounts= [int]$numberofuseraccounts+1
                    }
                                            
                    $finalout= @()
                    #find only lone occurences of true/false values
                                
                    foreach ($sortproperty in $sortproperties){    
                        $sketch= @()                
                        $result= $refinedoutput | Group-Object -Property $sortproperty                        
                        $result= $result | where {$_.count -le $numberofuseraccounts}
                        $propertyflagged= $sortproperty
                            
                        foreach ($i in $result.group){
                            $i.Propertyflagged = $propertyflagged
                            $i.Valueflagged = $i.$propertyflagged
                            $i.FlagDescription = "Outlying true/false value"
                            $i= $i | ConvertTo-Json
                            $sketch+= $i
                        }                    
                                
                        $finalout+= $sketch
                    }                        
                            
                    #grab all properties
                    $allproperties= $($refinedoutput[0] | get-member | where {$_.membertype -eq "noteproperty"})
        
                    #find occurences where the majority of the values are "NULL", but some aren't and vice versa
                    $nullproperties= $($allproperties | where {$_.definition -like "*=NULL"}).name | sort -unique
        
                    foreach ($nullproperty in $nullproperties){    
                        $sketch= @()                
                        $result= $refinedoutput | Group-Object -Property $nullproperty
        
                        if ($($result | where {$_.name -eq "Null"}).count -ge $numberofuseraccounts){                   
                            $result= $result | where {$_.count -le $numberofuseraccounts}
                            $propertyflagged= "$nullproperty"
                            $reason= "Value was not NULL when most others were NULL"
                        }
        
                        if ($($result | where {$_.name -eq "Null"}).count -le $numberofuseraccounts){                   
                            $result= $result | where {$_.name -eq "Null"}
                            $propertyflagged= "$nullproperty"
                            $reason= "Value was NULL when most others were not NULL"
                        }
                                
                        if ($result){
                        
                            foreach ($i in $result.group){
                                $i.Propertyflagged = $propertyflagged
                                $i.Valueflagged = $i.$propertyflagged
                                $i.FlagDescription = $reason
                                $i= $i | ConvertTo-Json
                                $sketch+= $i
                            }                                                        
                            
                            $finalout+= $sketch
                        }  
                    }
                        
                    #look for abnormally long values
                    $sketch= @()
                    $propertytable= @()
                    $propertytable+= "property,value,Length"
                    $allprops= $allproperties.name
        
                    foreach ($r in $refinedoutput){
                                
                        foreach ($a in $allprops){
                            $value= $r.$a.tostring()
                            $propertytable+= "$a,$value,$($value.length)"
                        }
                    }
        
                    $propertytable= $propertytable | convertfrom-csv
                            
                    foreach ($a in $allproperties){
                    
                        if ($a.name -eq "propertyflagged"){
                            continue
                        }
        
                        if ($a.name -eq "valueflagged"){
                            continue
                        }
        
                        $props= $($($propertytable | where {$_.property -eq "$($a.name)"}) | Group-Object -Property length)                       
                        
                        #Get the most common property length and find occurences where theres properties 10 chars larger
                        if ($props.name.count -ge 2){
                            [int]$commonprop= $($props | sort -Descending -Property count)[0].name
                            $prop= @()
        
                            foreach ($p in $props){
                            
                                if ([int]$p.name -ge $($commonprop + 10)){
                                    $prop+= $p
                                }
                            }                        
        
                            foreach ($p in $prop){
                                $propertyflagged= "$($a.name)-Length"
                                $p= $($propertytable | where {$_.length -eq "$($p.name)" -and $_.property -eq "$($a.name)"}).value | sort -Unique
                                                                      
                                foreach ($subproperty in $p){                                   
                                    $hit= $($refinedoutput | where {$_.$($a.name) -eq "$subproperty"})
                                    foreach ($h in $hit){
                                        $h.propertyflagged = $propertyflagged
                                        $h.valueflagged = $subproperty
                                        $h.flagdescription = "Length of value longer than normal"
                                        $h= $h | ConvertTo-Json
                                        $sketch+= $h                               
                                    }
                                }
                            }
                        }
                    }
                    $finalout+= $sketch
                }
        
                #look for Characters that might be out of the bounds of normal
                $sketch= @()
                $allproperties= $allproperties | where {$_.name -ne "Propertyflagged"}
                $allproperties= $allproperties | where {$_.name -ne "valueflagged"}
                $allproperties= $allproperties | where {$_.name -ne "FlagDescription"}
                
                foreach ($property in $allproperties){
                    $properties= $refinedoutput.$($property.name)
                    $properties= $properties | where {$_ -ne 'NULL'}
                    
                    if ($properties){
                        $table= @()
                        $table+= "value,low,high"
           
                        foreach ($p in $properties){
                            $value= $p
                        
                            if ($value){
                                $p= $p.tochararray()
                                $p= $p | % {[byte]$_}
                                $p= $p | sort -Descending | sort -Unique | where {$_}
                                $high= $p[-1]
                                $low= $p[0]
                                $table+= "$value,$low,$high"
                            }
                        }
                
                        $table= $table | convertfrom-csv
                        [int]$normal_low= $($table | Group-Object -Property low | sort -Descending -Property Count)[0].name
                        [int]$normal_high= $($table | Group-Object -Property high | sort -Descending -Property Count)[0].name
            
                        $lowhits= $($table | Group-Object -Property low | where {[int]$_.name -lt $normal_low -and $_.count -le 20}).group.value | sort -Unique
                        $highhits= $($table | Group-Object -Property high | where {[int]$_.name -gt $normal_high -and $_.count -le 20}).group.value | sort -Unique
                        
                        if ($lowhits){
                            foreach ($h in $lowhits){
                                $hit= $refinedoutput | where {$_.$($property.name) -eq $h}                    
                                $description= [char][int]$($table | where {$_.value -eq "$h"} | sort -Unique).low
        
                                foreach ($i in $hit){
                                    $i.propertyflagged = "$($property.name)"
                                    $i.Valueflagged = "$h"                        
                                    $i.FlagDescription = "The character ($description) was present in value" 
                                    $sketch+= $i | ConvertTo-Json
                                }
                            }
                        }
                        
                        if ($highhits){        
                            foreach ($h in $highhits){
                                $hit= $refinedoutput | where {$_.$($property.name) -eq $h}
                                $description= [char][int]$($table | where {$_.value -eq "$h"} | sort -Unique).high
        
                                foreach ($i in $hit){
                                    $i.propertyflagged = "$($property.name)"
                                    $i.Valueflagged = "$h"
                                    $i.FlagDescription = "The character ($description) was present in value" 
                                    $sketch+= $i | ConvertTo-Json
                                }
                            }            
                        }
                    }
                    $finalout+= $sketch
                }
                
                
                if ($finalout.count -gt 1){
                    $finalout= $finalout | convertfrom-json | select * | sort -Unique -Property samaccountname,valueflagged -ErrorAction SilentlyContinue                                    
                    new-item -ItemType Directory -name OutlyerAnalysis -Path $postprocessingpath\AnalysisResults -ErrorAction SilentlyContinue
                    $finalout= $finalout | ConvertTo-Csv -NoTypeInformation -ErrorAction SilentlyContinue

                    $finalout > $postprocessingpath\AnalysisResults\OutlyerAnalysis\ActiveDirectoryEnumeration-Analysis.csv
                }
                $end= Get-Date               
            }
        }  
                 
        function set-sensitivity{
            Remove-Variable -name sensitivity -Scope global -Force -ErrorAction SilentlyContinue
            clear-host
            header
            write-output "Choose sensitivty level for detecting outlyers"
            write-output "1.) High (Singletons only)"
            Write-Output "2.) Normal (Less than 1/2 the queried endpoints)"
            $sensitivity= read-host -Prompt " "
            New-Variable -name sensitivity -Value $sensitivity -ErrorAction SilentlyContinue -Scope global
        
            if ($sensitivity -ne "1" -and $sensitivity -ne "2"){
                clear-host
                Write-Output "Invalid Choice"
                sleep 2
                clear-host
                set-sensitivity
            }
        }
          
        Function identify-outlyers ($inputdata){
            $start= get-date
            new-item -ItemType Directory -Path $postprocessingpath\AnalysisResults -name OutlyerAnalysis -ErrorAction SilentlyContinue | out-null
            remove-variable -Name refinedoutput -Force -ErrorAction SilentlyContinue
            remove-variable -name output -Force -ErrorAction SilentlyContinue
        
            if (!$moduleconfiguration){
                $moduleconfiguration= Get-Content $env:USERPROFILE\Desktop\TheGreaterWall\Modules\Modules.conf | Convertfrom-csv -Delimiter :
                New-Variable -name obj -Value $($moduleconfiguration) -Force -ErrorAction SilentlyContinue
            }
            
            if ($moduleconfiguration){
                #parse File for selected data
                $settings= $obj | where {$_.p1 -eq "$inputdata"}
                $sortproperties= $($settings | where {$_.p2 -eq "Pivot"}).p3
                $ipproperty= $($settings | where {$_.p2 -eq "IP"}).p3
                $csvheader= $($settings | where {$_.p2 -eq "csvheader"}).p3

                if ($csvheader -ne "LEAVE-ORIGINAL"){
                    $csvheader= $csvheader + ",PropertyFlagged"
                }                
                
                #get contents of file
                $path= "$postprocessingpath\RawData\all_$inputdata.csv"
                $output= get-content $path -ErrorAction SilentlyContinue
                

                if (!$output){
                    Write-Host "[Warning] no $inputdata file" -ForegroundColor Red
                }
                
                if ($output){
                    $refinedoutput= $output | ConvertFrom-Csv
                
                    if ($sensitivity -eq "2"){
                        #define number of endpoints as half of the total count
                        $numberofendpoints= $($refinedoutput.$ipproperty | sort -Unique).count/2
                            
                        #round up if decimal
                        if ($numberofendpoints.ToString() | select-string "\."){
                            $numberofendpoints= $($numberofendpoints.tostring().split("\."))[0]
                            $numberofendpoints= [int]$numberofendpoints+1
                        }
                    }
                    
                    if ($sensitivity -eq "1"){
                        $numberofendpoints= "1"
                        $numberofendpointsOS = "1"
                    }
                                    
                    $sketch= @()
                    $finalout= @()
                    #find only lone occurences

                     ########OS GROUPS############
                    $operatingsystemgroups= $refinedoutput | group-object -Property operatingsystem
                    if ($operatingsystemgroups.count -gt 1){
                        
                        foreach ($o in $operatingsystemgroups){
                            $sketch= @()
                            $finalout= @()
                            $refinedoutputOS= $o.group

                            if (!$numberofendpointsOS){
                                $numberofendpointsOS= [math]::floor($([int]$($refinedoutputOS.hostname | Group-Object).name.count /2))
                            }

                            foreach ($sortproperty in $sortproperties){
                                
                                foreach ($i in $($($refinedoutputOS | Group-Object -Property $sortproperty | where {$_.count -le $numberofendpointsOS }).group)){
                                    $i= $($i | convertto-csv)-replace('"','')
                                    $i= $i[-1]
                                    $sketch+= "$i,$sortproperty"
                                }
                                    
                                #find occurences where it shows up more than once on a single endpoint    
                                foreach ($i in $($refinedoutputOS | Group-Object -Property $sortproperty | where {$($_.group.$ipproperty | sort -unique).count -le $numberofendpointsOS}).group){
                                    $i= $($i | convertto-csv)-replace('"','')
                                    $i= $i[-1]
                                    $sketch+= "$i,$sortproperty"   
                                }
                            }
                                                
                            $finalout+= $csvheader
                            $finalout+= $sketch | sort -Unique
                                                    
                            if ($finalout.count -gt 1){
                                new-item -path $postprocessingpath\AnalysisResults\OutlyerAnalysis\ -name OS_Specific_Outlyers -ItemType directory -ErrorAction SilentlyContinue
                                new-item -path $postprocessingpath\AnalysisResults\OutlyerAnalysis\OS_Specific_Outlyers -name $($o.name) -ItemType directory -ErrorAction SilentlyContinue
                                $finalout > $postprocessingpath\AnalysisResults\OutlyerAnalysis\OS_Specific_Outlyers\$($o.name)\$inputdata-Analysis.csv
                            }
                        }
                    }
                    ##########END OS GROUPS########### 
                    
                    $sketch= @()
                    $finalout= @()
                    foreach ($sortproperty in $sortproperties){
                        
                        foreach ($i in $($($refinedoutput | Group-Object -Property $sortproperty | where {$_.count -le $numberofendpoints }).group)){
                            $i= $($i | convertto-csv)-replace('"','')
                            $i= $i[-1]
                            $sketch+= "$i,$sortproperty"
                        }
                        
                        #find occurences where it shows up more than once on a single endpoint    
                        foreach ($i in $($refinedoutput | Group-Object -Property $sortproperty | where {$($_.group.$ipproperty | sort -unique).count -le $numberofendpoints}).group){
                            $i= $($i | convertto-csv)-replace('"','')
                            $i= $i[-1]
                            $sketch+= "$i,$sortproperty"   
                        }
                    }

                    $finalout+= $csvheader
                    $finalout+= $sketch | sort -Unique
                                                
                    if ($finalout.count -gt 1){  
                        $finalout > $postprocessingpath\AnalysisResults\OutlyerAnalysis\$inputdata-Analysis.csv
                    }
                }
            }  
        }
    
    
        ####################
        #Run post-Processor#
        ####################
    
        setup-workingenvironment
        setup-analysisenvironment
                
        if (!$postprocessingpath){
            break
        }

        ############################
        #Set the outlyer sensitivity
        ############################
        set-sensitivity

        #######################
        #Reformat all datasets#
        #######################
        clear-host
        write-output "Reformatting datasets"
        $totalstart= get-date
        $start= get-date
        
        #Extract the CSV potion of the PowerShell logs and write them to a csv file each endpoints post processing folder prior to building the master reference        
        
        if ($(Get-ChildItem $env:userprofile\desktop\TheGreaterWall\Results -Force -Recurse | where {$_.Parent -notlike "*postprocess*" -and $_.name -notlike "*postprocess*"} | where {$_.name -like "*powershell*"})){
             ExtractCSVFrom-PowerShellLogs
            ###################################
            #Build PowerShell Master Reference#
            ###################################
            #The building of this master reference is run as a background job but doesn't require receive-job because it writes to disk the whole time
            $action= $(get-item Function:\cleanpowershell-logs).ScriptBlock
            $actioncode = [scriptblock]::Create($action)
            start-job -ScriptBlock $actioncode -Name PowerShell_Log_Builder | Out-Null
            #Invoke-Command -ScriptBlock $actioncode -ComputerName 127.0.0.1 -JobName PowerShell_LOG_Builder -AsJob | Out-Null
            #######################################
            #END Build PowerShell Master Reference#
            #######################################
            #Add ip address to the content of each file, replacing the value "NULL" in the IP field of the CSV
        }

        #since this doesn't need to be done for the active directory results, just make a copy to the post processing location
        $files= Get-ChildItem -Force -Recurse $env:userprofile\Desktop\TheGreaterWall\Results -Depth 1 | where {$_.Attributes -ne "Directory"} -ErrorAction SilentlyContinue
        $file= $files | where {$_.name -like "*ActiveDirectory*"}
        $filename= $file.fullname
        $name= $file.name-replace('.txt','')
        $outputdirectory= get-childitem $postprocessingpath | where {$_.name -like "*ActiveDirectory*"}

        if ($outputdirectory){
            copy-item -Path $filename -Destination $outputdirectory\$name-postprocessed.csv -ErrorAction SilentlyContinue
        }
        
        #do the rest
        $files= Get-ChildItem -Force -Recurse $env:userprofile\Desktop\TheGreaterWall\Results -Depth 1 | where {$_.Attributes -ne "Directory"} -ErrorAction SilentlyContinue
        $files= $files | where {$_.name -notlike "*powershell*"} |  where {$_.name -notlike "*ActiveDirectory*"}

        foreach ($f in $files){
            $filename= $f.fullname
            $ip= $f.name.split('-')[0]
            $datatype= $f.name.split('-')[1]
            $outputdirectory= get-childitem $postprocessingpath | where {$_.name -like "*$ip*"}
            $content= get-content $filename | convertfrom-csv
                
            foreach ($c in $content){
                if ($c.ip -eq "NULL"){
                    $c.ip = $ip
                }
            }

            $content= $content | convertto-csv -NoTypeInformation
            $content >$filename

            #make new file with no headers in the postprocessingpath
            $content[1..($content.count)] >>$outputdirectory\$datatype-postprocessed_nh.csv
            $content >>$outputdirectory\$datatype-postprocessed.csv
        }                   
                
        $totalend= get-date
        $seconds= calculate-time $totalstart $totalend
        write-host "$(get-date)-- [Done] Reformatting $seconds" -ForegroundColor Green
        $start= get-date
    
        write-output "$(get-date)-- Concatenating"

        copyto-raw

        #get rid of _nh files
        $markfordeletion= $($postprocessfoldernames | % {Get-ChildItem $_ | where {$_.name -like "*_nh*"}}).fullname
        $markfordeletion | % {del $_}

        $end= get-date
        $seconds= calculate-time $start $end        
        Write-host "$(get-date)-- [Done] Concatenating $seconds" -ForegroundColor Green
        $start= get-date
        write-output "$(get-date)-- Cleaning up headers"
        cleanup-headers
        $end= get-date
        $seconds= calculate-time $start $end
        Write-host "$(get-date)-- [Done] Cleaning up headers $seconds" -ForegroundColor green

        ###################
        #Identify Outliers#
        ###################
        if ($results -lt 3){
            clear-host
            Header
            Write-Output " "
            Write-Output "Warning Only $results results sets available to analyze. You should have at least 3 results sets. Your analysis will be weak!"
            Write-output "If you have Active Directory results, those will still be analyzed with no issues."
            write-output " "
            pause
            $results= 3
        }

        if ($results -ge 3){
            $validinputdata= $(Get-Content $env:userprofile\desktop\thegreaterwall\modules\Modules.conf | convertfrom-csv -Delimiter :).p1 | sort -Unique            

            foreach ($v in $validinputdata){
                write-output "$(get-date)-- Identifying outlyers for $v"
                $start= get-date

                if ($v -eq "ActiveDirectoryEnumeration"){
                    identify-ActiveDirectoryOutlyers
                    $end= Get-Date
                    $seconds= calculate-time $start $end
                    write-host "$(get-date)-- [Done] Identifying outlyers for $v-- $seconds" -ForegroundColor Green
                }

                if ($v -ne "ActiveDirectoryEnumeration"){

                    identify-outlyers $v
                    $end= Get-Date
                    $seconds= calculate-time $start $end
                    write-host "$(get-date)-- [Done] Identifying outlyers for $v-- $seconds" -ForegroundColor Green
                }
            }
        }

         ###################
         #End Postprocessor#
         ###################
    }
    
    #Allows for an interactive session on a particular host
    function go-interactive{
        clear-host
        header
        write-output "            ****Interactive-mode****"
        write-output " "
        $endpoints= $listofips
        write-output "1.) Choose endpoint From list"
        write-output "2.) Enter IP or hostname manually"
        $choice= Read-Host -Prompt " "

        if ($choice -ne "1" -and $choice -ne "2"){
            clear-host
            write-output "Invalid selection"
            sleep 2
            go-interactive
        }

        if ($choice -eq "1"){
            clear-host
            header
            Write-output "Select an IP to go-interactive on"
            $x= 1
            $choicecontainer= @()
            $endpoints | % {$choicecontainer+= $_}
            $options= $endpoints | % {"$x.) $_"; $x++}
            $options
            $selection= Read-Host -Prompt " "
            
            if (!$options | Select-String "$selection.)" -ErrorAction SilentlyContinue){
                clear-host
                Write-Output "Invalid selection"
                sleep 2
                go-interactive
            }
            
            [string]$selection= [int]$selection -1
            $endpoint= $choicecontainer[$selection]
           
        }

        if ($choice -eq "2"){
            $regex= "^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])(\.(?!$)|$)){4}$"
            
            while ($endpoint | Select-String -NotMatch -Pattern $regex -ErrorAction SilentlyContinue){
                clear-host
                header
                Write-Output "Enter IP address that you wish to go-interactive on"
                $endpoint= Read-Host -Prompt " "

                if ($endpoint | Select-String -NotMatch -Pattern $regex){
                    clear-host
                    write-output "Invalid IP address. Try again."
                    sleep 2
                }
            }
        }
    
        remove-variable -name selection -ErrorAction SilentlyContinue

        while ($selection -ne "1" -and $selection -ne "2"){
            clear-host
            header
            write-output "You are about to go interactive on:"
            write-output $endpoint
            Write-Output " "
            write-output "1.) Continue"
            write-output "2.) Go back"
            $selection= Read-Host -prompt " "

            if ($selection -ne "1" -and $selection -ne "2"){
                Write-Output "Invalid selection"
                sleep 2
                clear-host
            }

            if ($selection -eq "2"){
                clear-host
                go-interactive
            }

            if ($selection -eq "1"){
                clear-host
                header
                write-output "Leaving TheGreaterWall and going interactive"
                $Params = @{
                FilePath     = "PowerShell.exe"
                ArgumentList = @(
                '-NoExit'
                "-Command Enter-PSSession -computername $endpoint -credential (get-credential)"
                
        
                    )
                }
                
                Start-Process @Params
             
            }   
        }
    }

    function save-config{
        $globalvars= @()
        $globalvars+= 'Name,Value'
        $globalvars+=  'playbook,null'
        $globalvars+=  'action,null'
        $globalvars+=  'activedirectoryconfiguration,null'
        $globalvars+=  'completedconnectiontest,null'
        $globalvars+=  'connectionstatus,null'
        $globalvars+=  'credentials,null'
        $globalvars+=  'datasets,null'
        $globalvars+=  'date,null'
        $globalvars+=  'DCcreds,null'
        $globalvars+=  'domaincontrollerip,null'
        $globalvars+=  'foldernames,null'
        $globalvars+=  'listofips,null'
        $globalvars+=  'loadedconf,null'
        $globalvars+=  'Logaggregatorchoice,null'
        $globalvars+=  'loglocal,null'
        $globalvars+=  'mode,null'
        $globalvars+=  'modstatus,null'
        $globalvars+=  'obj,null'
        $globalvars+=  'playbook,null'
        $globalvars+=  'postprocessfoldernames,null'
        $globalvars+=  'postprocessingpath,null'
        $globalvars+=  'resultspath,null'
        $globalvars+=  'securityonionip,null'
        $globalvars+=  'sensitivity,null'
        $globalvars+=  'setupstate,null'
        $globalvars+=  'splunkconfiguration,null'
        $globalvars+=  'tgw_logbeatconfiguration,null'       

    
        $globalvars= $globalvars | convertfrom-csv

        foreach ($g in $globalvars){
            $value= $(Get-Variable -name $g.name -ErrorAction SilentlyContinue).value
            $g.value= $value
        }
        $globalvars= $globalvars | convertto-json
        return $globalvars
    }

    #clears all global variables, and reload the framework
    function tgw-reset{
        $globalvars= @()
        $globalvars+= 'Name,Value'
        $globalvars+=  'playbook,null'
        $globalvars+=  'action,null'
        $globalvars+=  'activedirectoryconfiguration,null'
        $globalvars+=  'completedconnectiontest,null'
        $globalvars+=  'connectionstatus,null'
        $globalvars+=  'credentials,null'
        $globalvars+=  'datasets,null'
        $globalvars+=  'date,null'
        $globalvars+=  'DCcreds,null'
        $globalvars+=  'domaincontrollerip,null'
        $globalvars+=  'foldernames,null'
        $globalvars+=  'listofips,null'
        $globalvars+=  'loadedconf,null'
        $globalvars+=  'Logaggregatorchoice,null'
        $globalvars+=  'loglocal,null'
        $globalvars+=  'mode,null'
        $globalvars+=  'modstatus,null'
        $globalvars+=  'obj,null'
        $globalvars+=  'playbook,null'
        $globalvars+=  'postprocessfoldernames,null'
        $globalvars+=  'postprocessingpath,null'
        $globalvars+=  'resultspath,null'
        $globalvars+=  'securityonionip,null'
        $globalvars+=  'sensitivity,null'
        $globalvars+=  'setupstate,null'
        $globalvars+=  'splunkconfiguration,null'
        $globalvars+=  'tgw_logbeatconfiguration,null'
        $globalvars= $globalvars | convertfrom-csv
        foreach ($g in $globalvars){
            Remove-Variable -name $($g.name) -Scope global -force -ErrorAction SilentlyContinue
        }
        #get-module | where {$_.name -like "*activedirectory*"} | remove-module -Force -ErrorAction SilentlyContinue
        get-module | where {$_.name -like "*reformat*"} | Remove-Module -Force -ErrorAction SilentlyContinue
    tgw
    }

    #Lists descriptions for what the event log modules are
    function whatis ($query){
        remove-variable -Name done -Force -ErrorAction SilentlyContinue        
        $helppage= Get-ChildItem $env:userprofile\desktop\thegreaterwall\modules\module_help_pages | where {$_.name -like "*$query*"}
        $powershellMasterRef= Get-ChildItem $env:userprofile\desktop\thegreaterwall\tgwlogs\PowerShell_Master_Reference | where {$_.name -like "*$query*"}
        $query= "$query" + ".txt"

        #If the query term is found in both the helpdoc and the powershell master reference, prompt the user for clarification
        if ($helppage -and $powershellMasterRef -or !$query){
            clear-host
            write-output "Is $($query-replace('.txt','')) in reference to a powershell log?"
            write-output "1.) Yes"
            write-output "2.) No"
            $choice= Read-Host -Prompt " "
            clear-host
        
            if ($choice -eq 1){
                $file= $powershellMasterRef
                $msg= "Powershell Message Hash"
            }

            if ($choice -eq 2){
                $file= $helppage
                $msg= "Module Help page"
            }
                
            if ($file.count -eq 1){
                notepad $file.FullName
                $done= 1
            }

            if ($file.count -gt 1){
                $displaynames= $file | % {"$msg - $($_.name-replace('.txt',''))"}
                $choice= $displaynames | Out-GridView -Title "Multiple results found. Please Choose one." -PassThru
                if ($choice){
                    $choice= $choice.tostring().split('-')[1].trimstart(' ') + '.txt'
                    $choice= $file | where {$_.name -eq "$choice"}
                    notepad $choice.fullname
                }
                $done= 1
            }                
        }

        if ($powershellMasterRef -and $done -eq $null){
            $file= $powershellMasterRef
                
                if ($file.count -eq 1){
                    notepad $file.FullName
                    $done= 1
                }

                if ($file.count -gt 1){
                    $displaynames= $file | % {"Powershell Message Hash - $($_.name-replace('.txt',''))"}

                    $choice= $displaynames | Out-GridView -Title "Multiple results found. Please Choose one." -PassThru
                    if ($choice){
                        if ($choice -notlike "*collection*"){
                            $choice= $choice.tostring().split('-')[1].trimstart(' ') + '.txt'
                        }
    
                        if ($choice -like "*collection*"){
                            $choice= $choice.tostring().split('-')[1].trimstart(' ')
                            $choice= $choice-replace('.collection','.txt.collection')
                        }
    
                        $choice= $file | where {$_.name -eq "$choice"}
                    
                        if ($choice){
                            notepad $choice.fullname
                    
                        }
                        $done= 1
                    }
                }
        }
        
        if ($done -eq $null -and $helppage){
            $file= $helppage
                
                if ($file.count -eq 1){
                    notepad $file.FullName
                    $done= 1
                }

                if ($file.count -gt 1){
                    $displaynames= $file | % {"Module Help Page - $($_.name-replace('.txt',''))"}

                    $choice= $displaynames | Out-GridView -Title "Multiple results found. Please Choose one." -PassThru
                    $choice= $choice.tostring().split('-')[1].trimstart(' ') + '.txt'
                    $choice= $file | where {$_.name -eq "$choice"}
                    notepad $choice.fullname
                    $done= 1
                }

        }

        if (!$helppage -and !$powershellMasterRef){
            clear-host
            write-output "Reference to $($query-replace('.txt','')) not found."
            pause
            clear-host
        }
    }
       
    #displays available administrative commands
    function display-admincommands{
        clear-host
        write-output "--AVAILABLE FRAMEWORK ADMINISTRATION COMMANDS---"
        Write-Output "------------------------------------------------"
        Write-Output 'Command= "sync"                   Description= Forces background tasks to write their results to the appropriate location. -Very useful'
        Write-Output 'Command= "status"                 Description= Shows the status of all tasks you currently have deployed'
        write-output 'Command= "whatis"                 Description= Allows user to search message hashes for powershell logs or man page for a module (ex: whatis 8850, whatis prefetch)'
        write-output 'Command= "show-creds"             Description= Shows username and credential info that you previously defined'            
        write-output 'Command= "reset-creds"            Description= Allows you to repeat the part where you input the credentials'
        write-output 'Command= "show-targets"           Description= Shows list of IPs or hostnames that you previously defined'
        write-output 'Command= "add-target"             Description= Add to the IPs or hostnames that you previously defined'
        write-output 'Command= "remove-target"          Description= Remove IPs or hostnames that you previously defined'
        write-output 'Command= "reset-targets"          Description= Allows you to repeat the part where you input the IPs or hostnames'
        write-output 'Command= "hail-mary"              Description= Runs all modules on all targets, immediately'
        write-output 'Command= "tgw"                    Description= pops back into the framework, all user defined parameters are persistent'
        write-output 'Command= "go-interactive"         Description= Go into an interactive shell on an endpoint of your choosing'
        write-output 'Command= "run-connectiontest"     Description= Test WinRM connection for all endpoints, or specific endpoints'
        write-output 'Command= "show-connectionstatus"  Description= View Connectivity status for all targeted endpoints'
        write-output 'Command= "archive-results"        Description= Archive old results to avoid confusing them with current results'
        write-output 'Command= "module-status"          Description= Shows whether or not modules.conf contains a valid config for each module'
        write-output 'Command= "Reset-TGWLogbeat"       Description= Re-configure the settings for the TGW_Logbeat Forwarder'
        write-output 'Command= "uninstall-TGWLogbeat"   Description= Removes the (TGWLB) Service and Removes the files from C:\Windows\Temp'
        write-output 'Command= "beat-sync"              Description= Creates local event logs from results and forwards them to Security Onion'
        write-output 'Command= "splunk-sync"            Description= Creates local event logs from results and forwards them to splunk'
        write-output 'Command= "reset-splunk"           Description= Re-configure the settings for splunk forwarding'
        Write-Output 'Command= "reset-resultlocation"   Description= Reconfigure where the results from tunning the modules are output'
        write-output 'Command= "Modify-Auditpolicy"     Description= Enable or disable the logging behavior of the Target Endpoints'
        write-output 'Command= "Restore-Auditpolicy"    Description= Restore the Audit POlicy of Targets back to their default policy.'
        write-output 'Command= "back"                   Description= Go back to the main menu'
        write-output " "
        pause
    }

    #Prompt that allows you to choose between host and eventlog collection
    Function main-prompt{
        clear-host
        remove-variable -name choice -ErrorAction SilentlyContinue
        remove-variable -name menu -force -ErrorAction SilentlyContinue
        remove-variable -name modules -Force -ErrorAction SilentlyContinue
        Header
        Write-Output "Choose what type of actions you wish to perform"
        write-output " "
        write-output "1.) Host Collection"
        Write-Output "2.) EventLog Collection"
        Write-Output "3.) Post-process and analyze data"
        $choice= Read-Host -Prompt " "    
        
        if ($choice -eq "1"){
            $modules= "$env:userprofile\desktop\thegreaterwall\modules\hostcollection"
        }

        if ($choice -eq "2"){
            $modules= "$env:userprofile\desktop\thegreaterwall\modules\Eventlogs"
        }

        if ($choice -eq "3"){
            clear-host
            postprocessor
            clear-host
            write-output "Finished post processing at $(get-date)"
            sleep 2
            clear-host
            break
            
        }
    

        if ($choice -ne "1" -and $choice -ne "2" -and $choice -ne "3" -and $choice -ne "admin-commands"){
            clear-host
            write-host "Invalid Selection"
            sleep 1
            clear-host
            tgw
        }

        if ($choice -eq "admin-commands"){
            display-admincommands
            main-prompt
        }

        if ($choice -ne "admin-commands"){
            return $modules
        }
    }

    #Checks to see if the framework setup script has been completed, if not, it will perform any necessary setup actions
    function setup-framework{
        #check to see if setup happened, and if not, runs the setup to ensure the program functions

        if ($setupstate -ne "Complete"){
            #If the psmodule path doesnt contain the custom path, that means the setup never happened. 
            #checks to see the paths existence, and if it's not there, it runs the setup
            clear-host
            Get-ChildItem -Recurse $env:userprofile\desktop\thegreaterwall\modules | % {unblock-file $_.FullName}

            if (!$(get-childitem "$env:userprofile\Desktop\TheGreaterWall\modules")){
                $continuetosetup="Y"
            }
    
            if (!$(Get-ChildItem -force -Recurse "$env:userprofile\desktop\TheGreaterWall\modules" | Where-Object {$_.mode -like "*a*"})){
                $continuetosetup="Y"
            }
        
            if ($continuetosetup -eq "Y"){
                clear-host
                Header
                Write-Output "Framework Setup Not Complete"
                pause
                clear-host
                break
            }
    
            else{
                Header
                write-output "Framework setup already complete."
                sleep 1
                clear-host
                new-variable -name setupstate -value "complete" -Force -ErrorAction SilentlyContinue -Scope global
            }
        }

        set-location $env:userprofile\desktop\thegreaterwall
        $env:PSModulePath= "$env:userprofile\documents\windowspowershell\modules;c:\windows\system32\windowspowershell\v1.0\modules;$env:userprofile\desktop\TheGreaterWall\modules;$env:userprofile\desktop\TheGreaterWall\modules\eventlogs;$env:userprofile\desktop\TheGreaterWall\modules\hostcollection;$env:userprofile\desktop\TheGreaterWall\modules\Framework_dependency_modules"
        set-location $env:userprofile\desktop\thegreaterwall
    }

    #Displays the configuration of a module in modules.conf
    function module-status{
        $modulefolders= $(get-childitem $env:USERPROFILE\desktop\thegreaterwall\modules | where {$_.name -eq "EventLogs" -or $_.name -eq "HostCollection"}).fullname
        $mods= @()
    
        foreach ($m in $modulefolders){
        $mods+= $(Get-ChildItem $m).name | Sort -Unique
        }
    
        $modconfs= $(Get-Content $env:USERPROFILE\desktop\thegreaterwall\modules\modules.conf | ConvertFrom-Csv -Delimiter ":").p1 | sort -Unique
    
        $status= @()
        $status+= "Module,Config present in Modules.conf"
    
        foreach ($m in $mods){
            $config= $modconfs | select-string "$m"
    
            if ($config){
                $status+= "$m,Yes"
            }
    
            if (!$config){
                $status+= "$m,No"
            }
        }
        new-variable -name modstatus -value $($status | convertfrom-csv | sort -Property "Config present in Modules.conf" -Descending) -Scope global -ErrorAction SilentlyContinue
    }

    #Accepts user specified ip addresses in various formats, to include a file.
    function get-ipaddresses{
        function GenerateIPsFromCidr{
            Param(
            [Parameter(Mandatory = $true)]
            [array] $Subnets
            )
            foreach ($subnet in $subnets){
                
                #Split IP and subnet
                $IP = ($Subnet -split "\/")[0]
                $SubnetBits = ($Subnet -split "\/")[1]
                
                #Convert IP into binary
                #Split IP into different octects and for each one, figure out the binary with leading zeros and add to the total
                $Octets = $IP -split "\."
                $IPInBinary = @()
        
                foreach($Octet in $Octets){
                    #convert to binary
                    $OctetInBinary = [convert]::ToString($Octet,2)
                        
                    #get length of binary string add leading zeros to make octet
                    $OctetInBinary = ("0" * (8 - ($OctetInBinary).Length) + $OctetInBinary)
                    $IPInBinary = $IPInBinary + $OctetInBinary
                }
        
                $IPInBinary = $IPInBinary -join ""
                #Get network ID by subtracting subnet mask
                $HostBits = 32-$SubnetBits
                $NetworkIDInBinary = $IPInBinary.Substring(0,$SubnetBits)
                
                #Get host ID and get the first host ID by converting all 1s into 0s
                $HostIDInBinary = $IPInBinary.Substring($SubnetBits,$HostBits)        
                $HostIDInBinary = $HostIDInBinary -replace "1","0"
                #Work out all the host IDs in that subnet by cycling through $i from 1 up to max $HostIDInBinary (i.e. 1s stringed up to $HostBits)
                #Work out max $HostIDInBinary
                $imax = [convert]::ToInt32(("1" * $HostBits),2) -1
                $IPs = @()
                
                #Next ID is first network ID converted to decimal plus $i then converted to binary
                For ($i = 1 ; $i -le $imax ; $i++){
                    #Convert to decimal and add $i
                    $NextHostIDInDecimal = ([convert]::ToInt32($HostIDInBinary,2) + $i)
                    #Convert back to binary
                    $NextHostIDInBinary = [convert]::ToString($NextHostIDInDecimal,2)
                    #Add leading zeros
                    #Number of zeros to add 
                    $NoOfZerosToAdd = $HostIDInBinary.Length - $NextHostIDInBinary.Length
                    $NextHostIDInBinary = ("0" * $NoOfZerosToAdd) + $NextHostIDInBinary
                    #Work out next IP
                    #Add networkID to hostID
                    $NextIPInBinary = $NetworkIDInBinary + $NextHostIDInBinary
                    #Split into octets and separate by . then join
                    $IP = @()
                    
                    For ($x = 1 ; $x -le 4 ; $x++){
                        #Work out start character position
                        $StartCharNumber = ($x-1)*8
                        #Get octet in binary
                        $IPOctetInBinary = $NextIPInBinary.Substring($StartCharNumber,8)
                        #Convert octet into decimal
                        $IPOctetInDecimal = [convert]::ToInt32($IPOctetInBinary,2)
                        #Add octet to IP 
                        $IP += $IPOctetInDecimal
                    }
                    
                    #Separate by .
                    $IP = $IP -join "."
                    $IPs += $IP
                     
                }
                
                $IPs
            }
        }

        #this function outputs 2 GLOBAL variable2 named $listofips and $ipcount

        if (!$listofips -or $action -eq "reset-targets"){
            #New-Variable -name completedconnectiontest -value "No" -Force -ErrorAction SilentlyContinue -Scope global
            clear-host
            Header
            write-output "[The Greater Wall has the capability to threat hunt on multiple information systems.]`n"
            write-output "How would you like to specify the target endpoints?`n"
            write-output "1.) I have a .txt with a list of IP addresses.(One IP per line)"
            write-output "2.) I would like to use the IP Address entry tool."
            write-output "3.) I have a .txt with a list of hostnames. (One hostname per line)"
            write-output "4.) I would like to run The Greater Wall locally on this machine only."
            write-output " "
        
            $listofips= read-host -prompt "#TheGreaterWall"
            $regex= "^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])(\.(?!$)|$)){4}$"
                        
            if ($listofips -eq "1"){
                clear-host
                Header
                Write-Output "Please provide the file location of the IP addresses to investigate:`n"
                Write-Output "    Example: "`""$env:USERPROFILE\Desktop\ListofIPaddresses.txt"`"
                Write-Output "`n"
                $path= read-host -prompt "#TheGreaterWall"
                new-variable -name listofips -value $(get-content $path) -scope global -force
                $x= 1
            }

            if ($listofips -eq "3"){
                clear-host
                Header
                Write-Output "Please provide the file location of the hostnames to investigate:`n"
                Write-Output "    Example: "`""$env:USERPROFILE\Desktop\ListofHostNames.txt"`"
                Write-Output "`n"
                $path= read-host -prompt "#TheGreaterWall"
                new-variable -name listofips -value $(get-content $path) -scope global -force
                $x= 1
            }

            if ($listofips -eq "4"){
                $listofips= "localhost"
            }

            if ($listofips -eq "2"){
                clear-host
                Header
                write-output "Please provide the IP Address(es) you would like to investigate:`n"
                write-output "    Example: x.x.x.x, x.x.x.x, x.x.x.x`n"
                write-output "    Example: x.x.x.x/24`n"
                write-output "    Example: x.x.x.[1-15]`n"
                Write-output "    Example: x.x.x.x,x.x.x.x/24,x.x.x.[1-15]"
                write-output " "
                $listofips= $(Read-Host -Prompt "#TheGreaterWall")
                $listofips= $listofips.split(',').replace('"',"").TrimStart().trimend()       
                $allips= @()                   

                #calculate IPs from CIDR
                if ($listofips | select-string '/'){
                    $ips= $listofips | select-string '/'
                    foreach ($i in $ips){
                        $i= $i.tostring().TrimStart().trimend()
                        $ip= $i.split('/')[0]
                        $cidr= $i.split('/')[1]
                        
                        if ($cidr -lt "1" -or $cidr -gt "32"){
                            clear-host
                            write-output "Invalid CIDR."
                            write-output $i
                            sleep 2
                            Remove-Variable -name listofips -Force -ErrorAction SilentlyContinue
                            get-ipaddresses
                        }
                        $cidr= '/' + $i.split('/')[1]
                        $allips+= $(GenerateIPsFromCidr $ip$cidr)
                    }
                }

                #calculate IPs from range
                if ($listofips | select-string '\['){
                    $ips= $listofips | select-string "-"
                    $container= @()

                    foreach ($i in $ips){
                        $i= $i
                        $ip= $i.tostring().trimstart().TrimEnd().split('[')[0]
                        $range= $i.tostring().trimstart().TrimEnd().split('[')[1]
                        $range= $range.tostring().replace(']','')
                        $rangestart= $range.split('-')[0]
                        $rangeend= $range.Split('-')[1]


                        if ($rangestart -lt "1" -and $rangeend -gt "255"){
                            clear-host
                            Write-Output "Invalid Range."
                            Write-Output "$i"
                            sleep 2
                            Remove-Variable -name listofips -Force -ErrorAction SilentlyContinue
                            get-ipaddresses
                        }

                        $x= $rangestart

                        while ([int]$x -le [int]$rangeend){
                            $container+= "$ip"+"$x"
                            [int]$x= [int]$x+1
                        }
                    $allips+= $container
                    }
                }                                            

                #extract single IPs
                if ($($listofips | where {$_ -notlike "*/*"} | where {$_ -notlike "*-*"})){
                    $ips= $listofips | where {$_ -notlike "*/*"} | where {$_ -notlike "*-*"}
                    
                    foreach ($i in $ips){
                        $ip= $i.tostring().trimstart().trimend()
                        $allips+= $ip
                    }
                }                       

                #Bounce them off regex to check validity
                $badcontainer=@()
                $badcontainer+= "The Following Ips Are Invalid. You must retry."
                $badcontainer+= "-----------------------------"
          
                foreach ($a in $allips){
                    $valid= $a | select-string -Pattern $regex
               
                    if (!$valid){
                        $badcontainer+= $a
                    }
                }
                
                if ($badcontainer.count -gt 2){
                    clear-host
                    $badcontainer
                    pause
                    clear-host
                    remove-variable -name listofips -Force -ErrorAction SilentlyContinue
                    get-ipaddresses
                }
            }

            if ($x -ne 1 -and $listofips -eq "Localhost"){
                New-Variable -name listofips -Value "localhost" -Force -ErrorAction SilentlyContinue -Scope global
            }

            if ($x -ne 1 -and $listofips -ne "Localhost"){
                New-Variable -name listofips -Value $allips -Force -ErrorAction SilentlyContinue -Scope global
            }
        }
    }

    function remove-target{
    clear-host
    header
    write-output " "
    $endpoints= $listofips
    write-output "1.) Choose endpoint From list"
    write-output "2.) Enter IP manually"
    Write-Output "3.) Enter Hostname manually"
    Write-Output "4.) Go back"

    $choice= Read-Host -Prompt " "

    if ($choice -ne "1" -and $choice -ne "2" -and $choice -ne "3" -and $choice -ne "4"){
        clear-host
        write-output "Invalid selection"
        sleep 2
        remove-target
    }

    if ($choice -eq "1"){
        clear-host
        header
        Write-output "Select a target to remove. [Ctrl+C to abort]"
        $x= 1
        $choicecontainer= @()
        $endpoints | % {$choicecontainer+= $_}
        $options= $endpoints | % {"$x.) $_"; $x++}
        $options
        $selection= Read-Host -Prompt " "
        if (!$($options | where {$_ -like "$selection.)*"} -ErrorAction SilentlyContinue)){
            clear-host
            Write-Output "Invalid selection"
            sleep 2
            remove-target
        }
          
        [string]$selection= [int]$selection -1
        $endpoint= $choicecontainer[$selection]

        clear-host
        header
        Write-Output "Removing $endpoint"
        Write-Output " "
        pause
        $listofips= $listofips | where {$_ -ne "$endpoint"}
        Set-Variable -name listofips -value $listofips -Force -ErrorAction SilentlyContinue -Scope global
           
    }

    if ($choice -eq "2"){
       $regex= "^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])(\.(?!$)|$)){4}$"
         
        while ($endpoint | Select-String -NotMatch -Pattern $regex -ErrorAction SilentlyContinue){
            clear-host
            header
            Write-Output "Enter IP address that you wish to remove."
            $endpoint= Read-Host -Prompt " "

            if ($endpoint | Select-String -NotMatch -Pattern $regex){
                clear-host
                write-output "Invalid IP address. Try again."
                sleep 2
                remove-target
            }
        }

        if (!$($listofips | where {$_ -eq "$endpoint"})){
            clear-host
            Write-Output "$endpoint was not found in list of targets. Nothing to remove."
            sleep 2
        }
        
        if ($($listofips | where {$_ -eq "$endpoint"})){   
            Write-Output "Removing $endpoint"
            Write-Output " "
            pause
            $listofips= $listofips | where {$_ -ne "$endpoint"}
            Set-Variable -name listofips -value $listofips -Force -ErrorAction SilentlyContinue -Scope global
        }

    }
    
    remove-variable -name selection -ErrorAction SilentlyContinue

    if ($choice -eq "3"){
        clear-host
        header
        Write-Output "Enter hostname that you wish to remove."
        $endpoint= Read-Host -Prompt " "

        if (!$($listofips | where {$_ -eq "$endpoint"} -ErrorAction SilentlyContinue)){ 
            clear-host
            write-output "Invalid hostname. Try again."
            sleep 2
            remove-target
        }
        
        if ($($listofips | where {$_ -eq "$endpoint"})){
            clear-host
            Write-Output "$endpoint was not found in list of targets. Nothing to remove."
            sleep 2
        }

        if ($listofips | where {$_ -eq "$endpoint"}){
            Write-Output "Removing $endpoint"
            Write-Output " "
            pause
            $listofips= $listofips | where {$_ -ne "$endpoint"}
            Set-Variable -name listofips -value $listofips -Force -ErrorAction SilentlyContinue -Scope global
        }
    }

    if ($choice -eq "4"){
    }

clear-variable -name choice -Force -ErrorAction SilentlyContinue
 }
   
    function add-target{
    Clear-Variable -name endpoint -Force -ErrorAction SilentlyContinue
    clear-host
    header
    write-output " "
    $endpoints= $listofips
    write-output "1.) Enter IP manually"
    Write-Output "2.) Enter Hostname manually"
    Write-Output "3.) Go back"

    $choice= Read-Host -Prompt " "

    if ($choice -ne "1" -and $choice -ne "2" -and $choice -ne "3"){
        clear-host
        write-output "Invalid selection"
        sleep 2
        add-target
    }

    if ($choice -eq "1"){
       $regex= "^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])(\.(?!$)|$)){4}$"
         
        if (!$endpoint){
            clear-host
            header
            Write-Output "Enter IP address that you wish to add."
            $endpoint= Read-Host -Prompt " "

            if ($endpoint | Select-String -NotMatch -Pattern $regex){
                clear-host
                write-output "Invalid IP address. Try again."
                Remove-Variable -name endpoint -Force -ErrorAction SilentlyContinue
                sleep 2
                add-target
            }
        }

        if (!$($endpoint | Select-String -NotMatch -Pattern $regex)){

            if ($($listofips | where {$_ -eq "$endpoint"})){
                clear-host
                Write-Output "$endpoint already in list of targets."
                Remove-Variable -name endpoint -Force -ErrorAction SilentlyContinue
                sleep 2
            }        
    
            if (!$($listofips | where {$_ -eq "$endpoint"})){
                clear-host
                Write-Output "Adding $endpoint"

                if ($($listofips.count) -eq 0){
                    $listofips= @()
                }

                $listofips+= $endpoint
                Remove-Variable -name endpoint -Force -ErrorAction SilentlyContinue
                New-Variable -name listofips -Value $listofips -Force -ErrorAction SilentlyContinue -Scope global
                sleep 2
            }  
            remove-variable -name choice -ErrorAction SilentlyContinue   
        }    
    }

    if ($choice -eq "2"){
        clear-host
        header
        Write-Output "Enter hostname that you wish to add."
        $endpoint= Read-Host -Prompt " "

        if (!$($listofips | where {$_ -eq "$endpoint"} -ErrorAction SilentlyContinue)){ 
            clear-host
            write-output "Adding $endpoint."
            $listofips= $listofips+= $endpoint
            Set-Variable -name listofips -value $listofips -Force -ErrorAction SilentlyContinue -Scope global
            Remove-Variable -name endpoint -Force -ErrorAction SilentlyContinue
            sleep 2
        }
        
        if ($($listofips | where {$_ -eq "$endpoint"})){
            clear-host
            Write-Output "$endpoint already in list of targets. Nothing to add."
            Remove-Variable -name endpoint -Force -ErrorAction SilentlyContinue
            sleep 2
        }
    }

    if ($choice -eq "3"){
    }

    clear-variable -name choice -Force -ErrorAction SilentlyContinue
 }
    
    #Prompts the user to supply credentials that will allow for the authentication required to run the powershell modules
    function get-creds{
        if (!$credentials -or $action -eq "reset-creds"){
            clear-host

            Header
            write-output "[Warning] No Credentials detected"
            Write-Output "Do you wish to use credentials?`n"
            write-output "1.) Yes"
            Write-Output "2.) No`n"

            $choice= Read-Host -Prompt "#TheGreaterWall"
            
            if ($choice -eq "1"){

                if (!$credentials){
                    new-variable -name credentials -value $(Get-Credential) -force -Scope global
                }
    
                if ($credentials){
                    clear-host
                    Header
                    Write-Output "Credentials saved. Do you want to reset them?"
                    write-output "1.) Yes"
                    Write-Output "2.) No"
                    $choice= Read-Host -Prompt "#TheGreaterWall"
        
                    if ($choice -eq "1"){
                        new-variable -name credentials -value $(Get-Credential) -force -Scope global
                    }
                }
            }
        }
    }    
    
    function promptfor-configload{
        $conf= Get-Item -Path $env:userprofile\Desktop\Thegreaterwall\source\tgw_config.conf -ErrorAction SilentlyContinue
        if (!$loadedconf){
            if ($conf){
                clear-host
                header
                write-output "There's a saved configuration from $($conf.lastwritetime)"
                Write-Output "Would you like to apply this configuration?"
                write-output "1.) Yes"
                Write-Output "2.) No"
                $choice= Read-Host -Prompt " "
        
                if ($choice -eq 1){
                    #apply-config   
                    $tgwconf= Get-Content $env:userprofile\Desktop\Thegreaterwall\source\tgw_config.conf -ErrorAction SilentlyContinue | convertfrom-json

                    foreach ($t in $tgwconf){
                        new-variable -name $t.name -value $t.value -scope global -Force -ErrorAction SilentlyContinue
                    }
                    new-variable -name loadedconf -Value 1 -Scope global -Force -ErrorAction SilentlyContinue
                               
                }
        
                if ($choice -eq "2"){
                    clear-host
                }
        
                if ($choice -ne 1 -and $choice -ne 2){
                    clear-host
                    Write-Output "Invalid selection"
                    sleep 1
                    remove-variable -name choice -Force -ErrorAction SilentlyContinue
                    promptfor-configload
                }
            }
        }
    }
    #syncs results to SecOnion Via WinLogBeat
    function beat-sync{

        $log_ids= Get-Content $env:userprofile\Desktop\TheGreaterWall\Modules\Modules.conf | convertfrom-csv -Delimiter ":" | where {$_.p2 -eq "LogID"} | select p1,p3

        if ($logaggregatorchoice -eq "Splunkd"){
            $servicename= "Splunkd"
        }

        if ($logaggregatorchoice -eq "TGWLB"){
            $servicename= "TGWLB"
        }

        if ($logaggregatorchoice -eq "SplunkForwarder"){
            $servicename= "SplunkForwarder"
        }
                
        $service= get-service -name $servicename

        if ($service.Status -ne "Running"){
            clear-host
            header
            Write-host "[ERROR]"
            write-output "$logaggregatorchoice Service is not running. Nothing has been sync'd. Please fix the service and try again."
            Write-Output " "
            pause
            break
        }

        clear-host
        New-EventLog -LogName TGW -Source TGW -ErrorAction SilentlyContinue
        Limit-EventLog -LogName TGW -MaximumSize 4000000KB -ErrorAction SilentlyContinue
        
        $beatsync_SB={
            $log_ids= $args
            $dirs= get-childitem $env:USERPROFILE\Desktop\TheGreaterWall\results | where {$_.name -notlike "*Postprocess*" -and $_.name -notlike "*activedirectory*" -and $_.name -notlike "*log*"}
            $files=@()
            foreach ($d in $dirs){
                $files+= $(Get-ChildItem $d.FullName).fullname
            }

            #check to make sure you only sync the files that havent already been sync'd
            $alreadySyncd= Get-Content $env:USERPROFILE\Desktop\TheGreaterWall\TGWLogs\CompletedlogSyncs.txt
            
            if ($alreadySyncd){
                $filesToSync= $(Compare-Object $files $alreadySyncd | where {$_.sideindicator -eq "<="}).inputobject
            }

            if (!$alreadySyncd){
                $filesToSync= $files
            }

            foreach ($file in $filesToSync){
                $name= $file.split('-')[1]
                $logID= $($log_ids | where {$_.p1 -eq "$name"}).p3

                if (!$logID){
                    $logID= "200"
                }

                $fullname= $file
                $fullname>>$env:USERPROFILE\Desktop\TheGreaterWall\TGWLogs\CompletedlogSyncs.txt
                $content= Get-Content $fullname | convertfrom-csv
                        
                foreach ($c in $content){
                    $c= $c | convertto-json
                    Write-EventLog -LogName TGW -Source TGW -EntryType Warning -EventId $logID -Message $c
                }
            }
        }
    get-job | where {$_.name -like "*beat-sync*" -and $_.state -eq "Completed"} | Remove-Job
    start-job -ScriptBlock $beatsync_SB -ArgumentList $log_ids -Name "Beat-Sync$(1..1000 | get-random -count 1)"   
    }

    #Clears out finished background jobs and writes them to disk in their appropriate locations
    function get-allfinishedjobs{
        #get results of the finished jobs

        $finished= get-job | where {$_.state -eq "completed"}
        $errorjobs= get-job | where {$_.state -eq "Failed" -or $_.state -eq "Failed"}

        foreach ($job in $finished){
            $name= $job.name
            
            if ($name -like "*activedirectory*"){
                $filename= $name.split('-')[0] +".txt"
                $foldername= $name
            }

            if ($name -like "*-baseline-AppSvcLogs*"){
                $target= $($name-split("-"))[0]
                $content= get-job -id $($Job.id) | receive-job
                new-item -Path "$env:USERPROFILE\Desktop\TheGreaterWall\TgwLogs\" -Name Auditpol_backup -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
                $content | Out-File -FilePath $env:USERPROFILE\Desktop\TheGreaterWall\TgwLogs\Auditpol_backup\$($target)_Apps_Svc_Logs_backup.csv
            }

            if ($name -like "*baseline-AuditPolicy*"){
                $target= $($name-split("-"))[0]
                $content= get-job -id $($Job.id) | receive-job
                new-item -Path "$env:USERPROFILE\Desktop\TheGreaterWall\TgwLogs\" -Name Auditpol_backup -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
                $content | Out-File -FilePath $env:USERPROFILE\Desktop\TheGreaterWall\TgwLogs\Auditpol_backup\$($target)_auditpolicy_backup.csv
            }
                
            if ($name -like "*Auditpolicy*" -and $name -notlike "*baseline*"){
                $target= $($name-split("-"))[0]
                $content= get-job -id $($Job.id) | receive-job                
                $content= $content-replace("Target:NULL","Target: $target")
                $content | out-file -Append -FilePath $env:USERPROFILE\Desktop\TheGreaterWall\TgwLogs\OpNotes.txt
                remove-job -id $($job.id)                
            }

            if ($name -like "*AppSvcLogs*" -and $name -notlike "*baseline*"){
                $target= $($name-split("-"))[0]
                $content= get-job -id $($Job.id) | receive-job                
                $content= $content-replace("Target:NULL","Target: $target")
                $content | out-file -Append -FilePath $env:USERPROFILE\Desktop\TheGreaterWall\TgwLogs\OpNotes.txt
                remove-job -id $($job.id)                
            }

            else{
                $filename= $name+".txt"
                $foldername= $name.split('-')[0]
            }

            #get results of the finished jobs
            $results= get-job | where {$_.name -eq $name} | Receive-Job -ErrorAction SilentlyContinue                         
            
            if ($results){               
             $results | out-file -FilePath $env:USERPROFILE\Desktop\TheGreaterWall\results\$foldername\$filename
            }

            #remove the empty job
            get-job | where {$_.name -eq $name} | remove-job
        }
        
        if ($errorjobs){
            clear-host
            write-output "There are $($errorjobs.count) jobs with errors. Would you like to delete these jobs?"
            write-output "(The errors for these jobs can be found in $env:userprofile\Desktop\TheGreaterWall\TGWLogs\error.log)"
            write-output " "
            Write-Output "1.) Yes"
            write-output "2.) No"
            $choice= read-host -Prompt " "

            if ($choice -ne "1" -and $choice -ne "2"){
                clear-host
                write-output "Invalid selection."
                sleep 2
                get-allfinishedjobs
            }

            if ($choice -eq "1"){
                foreach ($e in $errorjobs){
                    remove-job -Name $($e.name)
                }
            }
        }
    }

    #Dynamic Menu that displays a menu of available modules. This menu will grow/shrink accordingly, depending on what modules you mave in the modules folder
    function display-menu ($modulepath){
        #Displays the menu of available commands based off of what is in the modules directory; dynamically updates as you update the directory

        clear-host
        #Build list of modules

        if ($modulepath | select-string -Pattern "^[0-9]\.\)"){
            clear-host
            break
        }

        $modules= $(Get-ChildItem $modulepath).name
        $mode= $($($modulepath.tostring().split('\'))[-1])

        if ($mode -eq "hostcollection"){
            $mode= "Host Collection"
            New-Variable -name mode -value $mode -Force -ErrorAction SilentlyContinue -Scope global
        }

        if ($mode -eq "EventLogs"){
            $mode= "Event Log Colllection"
            New-Variable -name mode -value $mode -Force -ErrorAction SilentlyContinue -Scope global
        }

        if ($loglocal -eq 2){
            $loglocation= "TGW event log on each remote computer"
        }

        if ($loglocal -eq 1){
            $loglocation= "On this device"
        }

        if ($loglocal -eq 3){
            $loglocation= "On this device and on each remote computer"
        }
    
        try{
            clear-host
            $menu=@()
            $menu+= $modules | % {$_.split(".")[0]}            
    
            #display menu for choice to be made
            $x= 1

            if ($credentials){
                $c= "Yes"
            }

            if (!$credentials){
                $c= "No"
            }

            header

            write-host "Additional administrative commands are available utilizing the syntax [Admin-Commands].`n"
            write-output "[ Mode: $mode | Credentials: $c | Targeted Endpoints: $($listofips.count) | Results Location: $loglocation]"
            write-output " "
            write-host "Select a module to run against targeted endpoints:`n"
            
            while ($x -le $($menu.count)){
                
                foreach ($m in $menu){
                    #Dynamic Menu
                    write-output "    $x.) $m"
                    $x++
                }
                write-output " "
            }
    
        }

        catch{
            write-output "****************"
            write-output "No Available Modules"
            write-output "****************"
            Write-Output " "
            break
        }
    }

    #Main prompt that stores the action you wish to perform in a variable
    function prompt-foraction{
        #This function outputs GLOBAL variable named $action

        Remove-Variable -name action -force -ErrorAction SilentlyContinue -Scope global
        new-variable -name action -value $(Read-Host '#TheGreaterWall') -force

        #check to see if the user is issuing framework administrative commands, number commands, or playbook commands

        if ($action.split(',').count -le 1){
            if ($($action | sls -Pattern "[0-9]{1,3}").Matches.value){
                [int]$action= $action
                Set-Variable -name action -Value $([int]$action) -scope global -force
            }
    
            if ($($action.gettype().name) -eq "String"){
                set-variable -name action -value $action -scope global -force
            }
        }

        if ($($action.gettype().name) -ne "Int32"){
            if ($action.split(',').count -gt 1){
                $action= $action.split(',')
                $action= $action | % {[int]$_}
                Set-Variable -name action -Value $($action) -scope global -force
                Set-Variable -name "playbook" -value "1" -scope global -Force            
            }
        }
    }
    #Main Execution
    #Run all setup functions

    Remove-Variable -name action -Force -ErrorAction SilentlyContinue
    setup-framework

    #Process raw commands if they are issued by the user
    if ($rawcommand -eq "splunk-sync"){
        clear-host
        beat-sync
        clear-host
        break
    }

    if ($rawcommand -eq "Beat-sync"){
        clear-host
        beat-sync
        clear-host
        break
    }

    if ($rawcommand -eq "postprocess"){
        clear-host
        postprocessor
        break
    }

    if ($rawcommand -eq "Reset"){
        tgw-reset        
    }
    
    #prompt for config load
    promptfor-configload
        

    #prompt for storage location
    if (!$loglocal){
        promptfor-Loglocal
    }

    #prompt the user for Splunk configuration params
    PromptFor-Splunk

    #prompt the user for TGW_Logbeat configuration params
    Setup-TGW_Logbeat

    #Import AD DLL
    $ad= $(get-module).name | where {$_ -like "*activedirectory*"}
    if (!$ad){

        if ($activedirectoryconfiguration -ne 0){
            import-activedirectory      
            clear-host
        }
    }

    #Prompt the user for the target IP Addresses
    get-ipaddresses

    #Prompt the user to run the connection test. All endpoints that fail the connection test will be excluded from the target list.
    get-wsmanconnection $listofips

    #Prompt the user for credentials
    if (!$credentials){
        get-creds
    }
         
    #Interpret additional Raw Commands issued from outside the framework

    #Show completion status of running tasks in a static list
    if ($rawcommand -eq "status"){
        clear-host
        write-output "--STATUS OF RUNNING TASKS--"
        $jobs= @()
        $jobs+= "Name,State,HasData"

        foreach ($j in $(get-job)){

            if ($j.state -eq "Running"){
                $name= $j.Name
                $state= $j.State
                $jobs+= "$name,$state,Undetermined"
            }

            if ($j.State -eq "Completed" -or $j.state -eq "Failed"){
                #makes $jobstatus and $joberror
                (Receive-Job $j -keep -OutVariable jobstatus -ErrorVariable joberror -ErrorAction SilentlyContinue) | out-null
                if ($joberror){
                    $name= $j.Name
                    $state= $j.state
                    $jobs+= "$name,$state,No Data. Error"
                    if (!$(get-content $env:userprofile\desktop\thegreaterwall\tgwlogs\error.log -ErrorAction SilentlyContinue | select-string $name)){
                        write-output "$(get-date)" >>$env:userprofile\desktop\thegreaterwall\tgwlogs\error.log
                        write-output "$($j.name)" >>$env:userprofile\desktop\thegreaterwall\tgwlogs\error.log
                        write-output "$joberror" >>$env:userprofile\desktop\thegreaterwall\tgwlogs\error.log
                        write-output "***********************************************************" >>$env:userprofile\desktop\thegreaterwall\tgwlogs\error.log
                    }
                }

                if ($jobstatus.length -gt 1){
                    $name= $j.Name
                    $state= $j.state
                    $jobs+= "$($j.name),$($j.state),Yes"
                }
            }
        }
            
        if ($jobs.count -eq 0){
            Write-Output "Nothing to display"
            Write-Output " "
        }
            
        else{
            $(get-variable -name jobs).value | convertfrom-csv | format-table
            Write-Output " "
        }
        pause
        clear-host
        break
    }         

    #Shw completion status of running tasks in a constantly refreshing list
    if ($rawcommand -eq "status-watch"){
        clear-host
        
        while ($true){
            clear-host
            write-output "--STATUS OF RUNNING TASKS--"
            write-output "Press CTRL + C to stop"
            $jobs= @()
            $jobs+= "Name,State,HasData"
    
            foreach ($j in $(get-job)){
    
                if ($j.state -eq "Running"){
                    $name= $j.Name
                    $state= $j.State
                    $jobs+= "$name,$state,Undetermined"
                }
    
                if ($j.State -eq "Completed" -or $j.state -eq "failed"){
                    #makes $jobstatus and $joberror
                    (Receive-Job $j -keep -OutVariable jobstatus -ErrorVariable joberror -ErrorAction SilentlyContinue) | out-null
                    $joberror= $joberror | out-string -stream

                    if ($joberror){
                        $name= $j.Name
                        $state= $j.state
                        $jobs+= "$name,$state,No Data. Error"
                        
                        #write errors to file only if there isnt one present already in the file
                        if (!$(get-content $env:userprofile\desktop\thegreaterwall\tgwlogs\error.log -ErrorAction SilentlyContinue | select-string $name)){
                            write-output "$(get-date)" >>$env:userprofile\desktop\thegreaterwall\tgwlogs\error.log
                            write-output "$($j.name)" >>$env:userprofile\desktop\thegreaterwall\tgwlogs\error.log
                            write-output "$joberror" >>$env:userprofile\desktop\thegreaterwall\tgwlogs\error.log
                            write-output "***********************************************************" >>$env:userprofile\desktop\thegreaterwall\tgwlogs\error.log
                        }
                    }
    
                    if ($jobstatus.length -gt 1){
                        $name= $j.Name
                        $state= $j.state
                        $jobs+= "$($j.name),$($j.state),Yes"
                    }
                }
            }
                
            if ($jobs.count -eq 0){
                Write-Output "Nothing to display"
                Write-Output " "
            }
                
            else{
                $(get-variable -name jobs).value | convertfrom-csv | format-table
                Write-Output " "
            }
            sleep 3
            clear-host
        }
    }
    
    #Clear out the tasks and write them to disk in their appropriate location
    if ($rawcommand -eq "sync"){
        clear-host
        get-allfinishedjobs
        set-location $env:userprofile\desktop\thegreaterwall\results
        break
    }

    #Compress the results and stash them away for later use
    if ($rawcommand -eq "archive-results"){
        clear-host
        archive-results
        set-location $env:userprofile\desktop\thegreaterwall\results
        clear-host
        break
    }
    
    #Actual Execution of framework modules

    while ($true){
        Remove-Variable -name action -Scope global -Force -ErrorAction SilentlyContinue
        Remove-Variable -name action -Force -ErrorAction SilentlyContinue
        #Display menu and header
        header

        if (!$poplocation){
            main-prompt | Tee-Object -Variable modulepath
            $modulepath= $modulepath[-1].tostring()
        }

        display-menu $modulepath | Tee-Object -Variable menu        

        #Prompt for action that you wish to execute
        prompt-foraction
        save-config

        $poplocation= 1

        #Evaluate action to see if its an admin command or an integer choice from the menu
        #if the datat type is an integer, jump to line 1200-ish

        if ($action.count -eq 1){
            $datatype= $action.gettype().name
        }

        if ($action.count -gt 1){
            $datatype= $($action | % {$_.gettype().name})[0]
        }

        #Check to see if the action is a string. If so, it is an 'admin command'
        if ($datatype -eq "String"){
                        
            if ($action -eq "archive-results"){
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
                clear-host
                archive-results
                clear-host
            }

            if ($action -eq "Uninstall-tgwlogbeat"){
                clear-host
                Uninstall-TGWLogBeat
                clear-host
            }

            if ($action -eq "go-interactive"){
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
                go-interactive
            }

            if ($action -eq "sync"){
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
                get-allfinishedjobs
                set-location $env:userprofile\desktop\thegreaterwall\results
            }

            if ($action -eq "beat-sync"){
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
                beat-sync
                set-location $env:userprofile\desktop\thegreaterwall\results
            }

            if ($action -eq "splunk-sync"){
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
                beat-sync
                set-location $env:userprofile\desktop\thegreaterwall\results
            }
        
            if ($action -eq "status"){
                clear-host
                write-output "--STATUS OF RUNNING TASKS--"
                $jobs= @()
                $jobs+= "Name,State,HasData"
    
                foreach ($j in $(get-job | where {$_.name -notlike "*beat-sync*"} | where {$_.name -notlike "*log_builder*"})){
    
                    if ($j.state -eq "Running"){
                        $name= $j.Name
                        $state= $j.State
                        $jobs+= "$name,$state,Undetermined"
                    }
    
                    if ($j.State -eq "Completed"){
                        #makes $jobstatus and $joberror
                        (Receive-Job $j -keep -OutVariable jobstatus -ErrorVariable joberror -ErrorAction SilentlyContinue) | out-null
                        if ($joberror){
                            $name= $j.Name
                            $state= $j.state
                            $jobs+= "$name,$state,No Data. Error"

                            if (!$(get-content $env:userprofile\desktop\thegreaterwall\tgwlogs\error.log -ErrorAction SilentlyContinue | select-string $name)){
                                write-output "$(get-date)" >>$env:userprofile\desktop\thegreaterwall\tgwlogs\error.log
                                write-output "$($j.name)" >>$env:userprofile\desktop\thegreaterwall\tgwlogs\error.log
                                write-output "$joberror" >>$env:userprofile\desktop\thegreaterwall\tgwlogs\error.log
                                write-output "***********************************************************" >>$env:userprofile\desktop\thegreaterwall\tgwlogs\error.log
                            }
                        }

                        if ($jobstatus.length -ge 1){
                            $name= $j.Name
                            $state= $j.state
                            $jobs+= "$($j.name),$($j.state),Yes"
                        }
                    }
                }
            
                if ($jobs.count -eq 1){
                    Write-Output "Nothing to display"
                    Write-Output " "
                }
                
                else{
                    $(get-variable -name jobs).value | convertfrom-csv | format-table
                    Write-Output " "
                }
                pause
                clear-host
            }         

            if ($action -eq "Run-Connectiontest"){
                New-Variable -name Completedconnectiontest -value "No" -Force -ErrorAction SilentlyContinue -Scope global
                get-wsmanconnection $listofips
            }

            if ($action -eq "reset-targets"){
                clear-host
                get-ipaddresses
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
            }

            if ($action -eq "reset-resultlocation"){
                clear-host 
                promptfor-Loglocal
                Remove-Variable -name action -force -ErrorAction SilentlyContinue
            }

            if ($action -eq "remove-target"){
                clear-host
                remove-target
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
            }

            if ($action -eq "add-target"){
                clear-host
                add-target
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
            }

            if ($action -eq "reset-activedirectoryconfig"){
                clear-host
                $activedirectoryconfiguration= 0
                Import-ActiveDirectory
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
            }
        
            if ($action -eq "reset-creds"){
                clear-host
                get-creds
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
            }

            if ($action -eq "reset-DCcreds"){
                clear-host
                Import-ActiveDirectory
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
            }
            
            if ($action -eq "Reset-TGWLogbeat"){
                clear-host
                Remove-Variable -name tgw_logbeatconfiguration -Scope global
                Uninstall-TGWLogBeat
                Setup-TGW_Logbeat
            }     

            if ($action -eq "Reset-splunk"){
                clear-host
                Remove-Variable -name splunkconfiguration -Scope global
                PromptFor-Splunk
            }                
                               
            if ($action -eq "hail-mary"){
                clear-host
                write-host "You've selected HAIL-MARY. This runs all $mode modules on all targets"
                Write-Host " "
                write-host "1.) Continue with Host Collection hail-mary"
                write-host "1.) Continue with Event Log hail-mary"
                write-host "3.) Go back"
                $choice= Read-Host -Prompt " "
                clear-host

                if ($choice -eq "1"){
                    $action= $(Get-childitem -Recurse $env:userprofile\Desktop\TheGreaterWall\Modules\hostcollection | where {$_.mode -like "*a*"}).name
                    $action= $action | % {$_.tostring()-replace('.psm1','')} | Sort -Unique
                    Set-Variable -name action -value $action -force -Scope global                    
                }
                            

                if ($choice -eq "2"){
                    $action= $(Get-childitem -Recurse $env:userprofile\Desktop\TheGreaterWall\Modules\EventLogs | where {$_.mode -like "*a*"}).name
                    $action= $action | % {$_.tostring()-replace('.psm1','')} | Sort -Unique
                    Set-Variable -name action -value $action -force -Scope global
                }                
         
                else{
                }
              
            }

            if ($action -eq "admin-commands"){
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue -Scope global
                display-admincommands
            }
            
            if ($action -eq "save-config"){
                save-config | out-file $env:userprofile\Desktop\Thegreaterwall\source\tgw_config.conf -Force -ErrorAction SilentlyContinue
                clear-host
            }      
            
            if ($action -eq "Back"){
                Remove-Variable -name poplocation -Force -ErrorAction SilentlyContinue
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
                continue
            }


            if ($action -eq "show-connectionstatus"){
                clear-host
                header
                write-output "     IP          WINRM          PING"
                write-output "***************************************"
            
                foreach ($i in $connectionstatus){
                        Write-Output "$($i.computername) | $($i.winrm) | $($i.ping)"
                    }
                write-output " "
                pause
            }

            if ($action -eq "module-status"){
                clear-host
                header
                module-status
                $modstatus | out-string -Stream
                pause
                remove-variable -name modstatus -Force -ErrorAction SilentlyContinue
            }

            if ($action -eq "show-creds"){
                clear-host
                write-output "You are operating with creds from the follwing user account:"
                write-output "- $($credentials.UserName)"
                write-output " "
                pause
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
            }

            if ($action -eq "show-DCcreds"){
                clear-host
                write-output "Domain Controller Credentials:"
                write-output "- Username: $($($DCcreds).username)    IP: $domaincontrollerip"
                write-output " "
                pause
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
            }
            
            if ($action -like "whatis*"){
                $query= $($action.split(' '))[1]
                clear-host
                header
                whatis "$query"                
                Write-Host " "              
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
            }

            if ($action -eq "show-targets"){
                clear-host
                $listofips
                pause
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
            }          
            
            if ($action -eq "tgw"){
                clear-host
                write-output "You are already in the framework. This command is only used to get back into the framework from a shell session"
                Remove-Variable -name action -Force -ErrorAction SilentlyContinue
                pause
            }
            
            if ($action -eq "Modify-AuditPolicy"){
                Remove-Variable -name success -Force -ErrorAction SilentlyContinue
                Remove-Variable -name failure -Force -ErrorAction SilentlyContinue
                $allevent_Ids= Get-Content $env:userprofile\Desktop\TheGreaterWall\Source\all_securitylogs.conf | convertfrom-csv
                $all_application_and_services_logs= Get-Content $env:USERPROFILE\Desktop\TheGreaterWall\Source\All_Applications_and_services_logs.conf | convertfrom-csv
                clear-host
                header
                write-output "Choose an option below to enable an event Log"
                Write-Output "1.) Manually type one or more Windows Security Event Log IDs"
                Write-Output "2.) Choose from a list or Security Logs"
                write-output "3.) Choose from a list of Applications and Services Logs" 
                Write-Output " "
                $choice= read-host -Prompt " "

                if ($choice -ne "1" -and $choice -ne "2" -and $choice -ne 3){
                    clear-host
                    write-output "Invalid Selection"
                    sleep 1
                    clear-host
                }

                if ($choice -eq "2"){
                    $logs= $allevent_Ids | Out-GridView -PassThru
                }

                if ($choice -eq "1"){
                    clear-host
                    header
                    Write-Output "Please type one or more Log Ids"
                    Write-Output "(Example: 4688,4624,5156)"
                    write-output  " "
                    $userinput= read-host -Prompt " "
                    $userinput= $userinput.split(',').trimstart().trimend()
                    
                    $logs= @()
                    foreach ($u in $userinput){
                        $logs+= $allevent_Ids | where {$_.log -eq "$u"}
                    }
                }

                if ($choice -eq "3"){
                    function BaselineWindowsLogs{
                        $windowslogs= @()
                        $windowslogs+= "Logname,Setting"
                        
                        foreach ($l in $(Get-WinEvent -ListLog *)){
                            $windowslogs+= "$($l.logname),$($l.isenabled)"
                        }
                        $windowslogs
                    }
                    
                    $logs= $all_application_and_services_logs.description | Out-GridView -PassThru -Title "Choose one or More Applications and Services Log"
                    $commands= @()
                    $commands+= 'Start-sleep -seconds 60'

                    foreach ($l in $logs){
                        $commands+= $($($all_application_and_services_logs | where {$_.description -eq "$l"}).command)
                    }
                    
                    $commands+= "write-output 1"

                    $actioncode = [scriptblock]::Create($commands-join(';'))
                }

                clear-host
                header
                write-output "You are about to enable the following logs on all $($listofips.count) target(s)"
                Write-Output " "

                foreach ($l in $logs){
                    if ($($l.description)){
                        $l.description
                    }

                    if (!$($l.description)){
                        $l
                    }
                }
                write-output " "
                pause

                if ($choice -eq "3"){
                    #Get baseline
                    $baseline= [scriptblock]::Create($(get-content Function:\BaselineWindowsLogs))
                    $date= (Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join ""
                    
                    foreach ($ip in $listofips){
                        $backupfile= "$env:userprofile\desktop\TheGreaterWall\TgwLogs\AuditPol_backup\" + "$ip" + "_Apps_Svc_Logs_backup.csv"
                        
                        if (!$(get-item -Path $backupfile -ErrorAction SilentlyContinue)){
                            invoke-command -ScriptBlock $baseline -ComputerName $ip -Credential $credentials -JobName "$ip-baseline-AppSvcLogs-$date" -AsJob
                            $opnotes=@()
                            $date= "[ " + $((Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join "") + " ]"
                            $opnotes+= $date
                            $opnotes+= "*************************************"
                            $opnotes+= "Action: Baselined Audit Policy"
                            $opnotes+= "Target:$ip"
                            $opnotes+= "Commands Executed:"
                            $opnotes+= $baseline.tostring().split(';')
                            $opnotes | out-file -Append -FilePath $env:userprofile\Desktop\TheGreaterWall\TgwLogs\Opnotes.txt
                        }
                    }

                    #make Changes
                    foreach ($ip in $listofips){
                        invoke-command -ScriptBlock $actioncode -ComputerName $ip -Credential $credentials -JobName "$ip-Modify-AppSvcLogs-$date" -AsJob                    
                        #write to TGW Logs for Opnotes
                        $opnotes=@()
                        $date= "[ " + $((Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join "") + " ]"
                        $opnotes+= $date
                        $opnotes+= "*************************************"
                        $opnotes+= "Action: Modified Audit Policy"
                        $opnotes+= "Target:$ip"
                        $opnotes+= "Commands Executed:"
                        $opnotes+= $actioncode.tostring().split(';')
                        $opnotes | out-file -Append -FilePath $env:userprofile\Desktop\TheGreaterWall\TgwLogs\Opnotes.txt
                    }
                }                    

                if ($choice -eq "1" -or $choice -eq "2"){
                    #Create Scriptblock to baseline the current auditpolicy
                    $action={function Build-PolicyObject{
                    $auditpol_categories= $(C:\windows\system32\auditpol.exe /get /category:* | select-string -Pattern ^[A-Z])
                    $auditpol_categories= $auditpol_categories[2..$($auditpol_categories.count)]
                    $policy_obj=@("Category,Subcategory, Policy")
                                               
                    foreach ($c in $auditpol_categories){
                        $subcategories= C:\windows\system32\auditpol.exe /get /category:$c | select-string -Pattern ^" "
                        foreach ($s in $subcategories){
                            $s= $s.tostring()-split('  ') | % {$_.trimstart().trimend()}
                            $policy_obj+= "$($c.tostring()),$($s[1]),$($s[$($s.count -1)])"
                            }
                        }
                    $policy_obj
                    }
                    Build-PolicyObject
                    }
                    $date= (Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join ""
                    $actioncode= [scriptblock]::Create($action)
                    
                    foreach ($ip in $listofips){
                        $backupfile= "$env:userprofile\desktop\TheGreaterWall\TgwLogs\AuditPol_backup\" + "$ip" + "_auditpolicy_backup.csv"
                        if (!$(get-item -Path $backupfile -ErrorAction SilentlyContinue)){
                            invoke-command -ScriptBlock $actioncode -ComputerName $ip -Credential $credentials -JobName "$ip-baseline-Auditpolicy-$date" -AsJob
                        }
                    }
    
                    #create Scriptblock to Change Audit policy
                    $action=@()                    
                    $action+= $logs.command-join(';')
                    $action= 'start-sleep -seconds 60;' + $action
                    $date= (Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join ""
                    $actioncode = [scriptblock]::Create($action)
    
                    foreach ($ip in $listofips){                  
                        
                        invoke-command -ScriptBlock $actioncode -ComputerName $ip -Credential $credentials -JobName "$ip-Modify-Auditpolicy-$date" -AsJob
                       
                        #write to TGW Logs for Opnotes
                        $opnotes=@()
                        $date= "[ " + $((Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join "") + " ]"
                        $opnotes+= $date
                        $opnotes+= "*************************************"
                        $opnotes+= "Action: Modified Audit Policy"
                        $opnotes+= "Target:$ip"
                        $opnotes+= "Commands Executed:"
                        $opnotes+= $action.split(';')
                        $opnotes | out-file -Append -FilePath $env:userprofile\Desktop\TheGreaterWall\TgwLogs\Opnotes.txt
                    }
                    clear-host
                    header
                    Write-Output " "
                    Write-Output "You've changed the audit policy on $($listofips.count) Target(s)."
                    write-output "In order for The Greater Wall to process the request, it must exit."
                    Write-Output "Please type TGW to get back info the framework after pressing enter."
                    write-output " "
                    remove-variable -name action -Scope global -Force -ErrorAction SilentlyContinue
                    pause
                    break                            
                }  
            }

            if ($action -eq "Restore-Auditpolicy"){
                foreach ($ip in $listofips){                   
                    $original_Policy= "$env:userprofile\Desktop\TheGreaterWall\TgwLogs\Auditpol_backup\" + "$ip" + "_auditpolicy_backup.csv"
                    $original_Policy= Get-Content $original_Policy -ErrorAction SilentlyContinue | convertfrom-csv -ErrorAction SilentlyContinue
                    $original_appsvclog= "$env:userprofile\Desktop\TheGreaterWall\TgwLogs\Auditpol_backup\" + "$ip" + "_Apps_Svc_Logs_backup.csv "
                    $original_appsvclog= Get-Content $original_appsvclog -ErrorAction SilentlyContinue | ConvertFrom-Csv -ErrorAction SilentlyContinue

                    if ($original_Policy){
                        $original_Policy | Add-Member -NotePropertyName "Command" -NotePropertyValue "$null"

                        foreach ($o in $original_Policy){
                            if ($o.policy -eq "Success"){
                                $o.command = "C:\windows\system32\auditpol.exe /set /subcategory:" + '"'+ $($o.subcategory) + '" ' + "/Success:Enable /failure:Disable"
                            }
    
                            if ($o.policy -eq "Failure"){
                                $o.command = "C:\windows\system32\auditpol.exe /set /subcategory:" + '"'+ $($o.subcategory) + '" ' + "/Success:Disable /failure:Enable"
                            }
    
                            if ($o.policy -eq "Success and Failure"){
                                $o.command = "C:\windows\system32\auditpol.exe /set /subcategory:" + '"'+ $($o.subcategory) + '" ' + "/Success:Enable /failure:Enable"
                            }
    
                            if ($o.policy -eq "No Auditing"){
                                $o.command = "C:\windows\system32\auditpol.exe /set /subcategory:" + '"'+ $($o.subcategory) + '" ' + "/Success:Disable /failure:Disable"
                            }
                        }  
                    }

                    if ($original_appsvclog){
                        $original_appsvclog | Add-Member -NotePropertyName "Command" -NotePropertyValue "$null"
                       
                        foreach ($o in $original_appsvclog){
                            $command= '$log= ' + "New-Object System.Diagnostics.Eventing.Reader.EventLogConfiguration " + '"' + $($o.logname) + '"' + ";" + '$log' + '.IsEnabled=' + '$' + "$($o.setting)" + ';try{$log.SaveChanges()}catch{}'
                            $o.command = $command
                        }
                    }


                    #prepare to restore the Audit policy
                    $action=@()
                    $action+= $original_Policy.command-join(';')
                    $action+= $original_appsvclog.command-join(';')
                    $date= (Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join ""
                    $actioncode = [scriptblock]::Create($action)

                    #clear-host
                    header
                    write-output "You are about to restore the audit policies on $($listofips.count) target(s) back to their default."
                    write-output " "
                    invoke-command -ScriptBlock $actioncode -ComputerName $ip -Credential $credentials -JobName "$ip-Restore-Auditpolicy-$date" -AsJob                              
                   
                    #write to TGW Logs for Opnotes
                    $opnotes=@()
                    $date= "[ " + $((Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join "") + " ]"
                    $opnotes+= $date
                    $opnotes+= "*************************************"
                    $opnotes+= "Action: Restored Audit Policy back to default"
                    $opnotes+= "Target:$ip"
                    $opnotes+= "Commands Executed:"
                    $opnotes+= $action.split(';')
                    $opnotes | out-file -Append -FilePath $env:userprofile\Desktop\TheGreaterWall\TgwLogs\Opnotes.txt
                }             
              
                clear-host
                header
                Write-Output " "
                Write-Output "You've changed the audit policy on $($listofips.count) Target(s)."
                write-output "In order for The Greater Wall to process the request, it must exit."
                Write-Output "Please type TGW to get back info the framework after pressing enter."
                write-output " "
                remove-variable -name action -Scope global -Force -ErrorAction SilentlyContinue
                pause
                break  
            }    
        }

        #Check to see if hailmary was desired action. If there is more than 1 action its hail-mary.
        if ($action.count -gt 1){        
            #hail-mary
            clear-host
            if ($playbook -ne 1){
                write-output "Executing hail-mary"
            }
            if ($playbook -eq 1){
                Set-Variable -name playbook -value 0 -Force -ErrorAction SilentlyContinue -Scope global
                Write-Output "Running Selected modules"
                $actioncontainer= @()
                foreach ($a in $action){
                    $index= $a-1
                    $actioncontainer+= $(Get-ChildItem $modulepath)[$index].name
                }
                $action= $actioncontainer
            }

            sleep 2           

            foreach ($a in $action){
                LogTo-Opnotes $action
                #The active directory module needs to be executed differently, because not every targeted endpoint needs to query AD. It would be too redundant.
                
                if ($a -like "*activedirectory*"){
                    
                    if (!$activedirectoryconfiguration -or $activedirectoryconfiguration -eq "0"){
                        clear-host
                        header
                        write-output "Active Directory settings aren't configured."
                        Write-Output 'You must configure it.'
                        pause
                        Import-ActiveDirectory
                    }

                    if ($activedirectoryconfiguration -or $activedirectoryconfiguration -eq "1"){
                        $date= (Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join ""
                        new-item -name $a-$date -Path $env:USERPROFILE\desktop\TheGreaterWall\results -ItemType Directory -ErrorAction SilentlyContinue                         
                        $filename= "$a-$date.txt"    
                        import-module $a
                        import-module $a
                        $module= get-module -name $a
                        $modulename= $module.name
                        $actioncode= $module.Definition
                        $actioncode= $actioncode-replace('Export-ModuleMember -Function ','')
                        $actioncode = [scriptblock]::Create($actioncode)
                        Remove-Module -name $modulename
                        
                        $option = New-PSSessionOption -nomachineprofile
                        $dcsesh= New-PSSession -name dcsesh -ComputerName $domaincontrollerip -Credential $DCcreds -SessionOption $option
                        Invoke-Command -ScriptBlock $actioncode -jobname "$modulename-$date" -Session $dcsesh 
                    } 
                }


                else{
                    foreach ($ip in $listofips){
                        new-item -name $ip -Path $env:USERPROFILE\desktop\TheGreaterWall\results -ItemType Directory -ErrorAction SilentlyContinue     
                        $date= (Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join ""
                        $filename= "$ip-$a-$date.txt"    
                        import-module $a
                        $module= get-module -name $a
                        $modulename= $module.name
                        $actioncode= $module.Definition
                        $actioncode= $actioncode-replace('Export-ModuleMember -Function ','')
                        $actioncode = [scriptblock]::Create($actioncode)
                        Remove-Module -name $modulename
                            
                        if ($listofips -eq "localhost"){
                            $hostname= $env:COMPUTERNAME
                            invoke-command -ScriptBlock $actioncode -computername 127.0.0.1 -JobName "127.0.0.1-$a-$date" -AsJob 
                        }

                        if ($listofips -ne "localhost"){
                            invoke-command -ScriptBlock $actioncode -ComputerName $ip -Credential $credentials -JobName "$ip-$a-$date" -AsJob 
                        }                                  
                    }                                            
                }            
                remove-variable -name action -Force -ErrorAction SilentlyContinue
            }                    
        }

        #Check to see if it is an integer (aka a menu selection)
        if ($datatype -eq "Int32"){
            try{
                #Extract selection and convert number selection to corresponding module name
                 $action= $action-1
                 $action= $(Get-ChildItem $modulepath)[$action].name              
                    
                #Display a message about the module that will soon be executed
                clear-host
                if ($action -like "*activedirectory*"){
                    write-host "Running $action"
                }

                else{
                    write-host "Running $action on $($listofips.count) IP(s)"
                }

                sleep 2
            }
    
            catch{
                write-output "No modules to execute"
            }

            if ($action.count -eq 1){
                #Single Action
                #check to make sure its a valid action
                $availableactions= $(Get-childitem -Recurse $env:userprofile\Desktop\TheGreaterWall\Modules | where {$_.Extension -eq ".psm1"}).name
                $availableactions= $availableactions | % {$_-replace('.psm1','')}
                
                #If the action is not valid, display an error
                if ($availableactions -notcontains $action){
                    clear-host
                    Write-Output "Invalid action"
                    sleep 2
                    clear-host
                }
                
                #If the action is valid, continue on to execution
                if ($availableactions -contains $action){
                    LogTo-Opnotes $action

                    #The active directory module needs to be executed differently, because not every targeted endpoint needs to query AD. It would be too redundant.
                    if ($action -like "*activedirectory*"){
                        
                        if (!$activedirectoryconfiguration -or $activedirectoryconfiguration -eq "0"){
                            clear-host
                            header
                            write-output "Active Directory settings aren't configured."
                            Write-Output 'You must configure it.'
                            pause
                            Import-ActiveDirectory
                        }

                        if (!$activedirectoryconfiguration -or $activedirectoryconfiguration -eq "0"){
                            $date= (Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join ""
                            new-item -name $action-$date -Path $env:USERPROFILE\desktop\TheGreaterWall\results -ItemType Directory -ErrorAction SilentlyContinue                         
                            $filename= "$action-$date.txt"    
                            import-module $action
                            $module= get-module -name $action
                            $modulename= $module.name
                            $actioncode= $module.Definition
                            $actioncode= $actioncode-replace('Export-ModuleMember -Function ','')
                            $actioncode = [scriptblock]::Create($actioncode)
                            Remove-Module -name $modulename

                            $option = New-PSSessionOption -nomachineprofile
                            $dcsesh= New-PSSession -name dcsesh -ComputerName $domaincontrollerip -Credential $DCcreds -SessionOption $option
                            Invoke-Command -ScriptBlock $actioncode -jobname "$modulename-$date" -Session $dcsesh  
                        }                  
                    }

                    else{
                        foreach ($ip in $listofips){
                            new-item -name $ip -Path $env:USERPROFILE\desktop\TheGreaterWall\results -ItemType Directory -ErrorAction SilentlyContinue 
                            $date= (Get-Date -Format "dd-MMM-yyyy HH:mm").Split(":") -join ""
                            $filename= "$ip-$action-$date.txt"
                            import-module $action    
                            $actioncode= $(get-module -name $action).Definition                                                        

                            if ($loglocal -eq 2 -or $loglocal -eq 3){
                                $logid= $(Get-Content $env:USERPROFILE\desktop\thegreaterwall\modules\modules.conf | convertfrom-csv -Delimiter ':' | where {$_.p1 -eq $action -and $_.p2 -eq "LogID"}).p3
                                $replacementstring= '$'+'content= '+"$action`n" + "`n" + "New-EventLog -LogName TGW -Source TGW -ErrorAction SilentlyContinue`n"+"Limit-EventLog -LogName TGW -MaximumSize 4000000KB -ErrorAction SilentlyContinue`n"+'foreach ($c in $content){'+"`n"+"`t"+'$c= $c | convertto-json' + "`n"+"`tWrite-EventLog -LogName TGW -Source TGW -EntryType Warning -EventId $logID -Message" + ' $c' +"`n"+'}'
                                $string2replace= "Export-ModuleMember -Function $action"
                                $actioncode= $actioncode-replace("$string2replace","$replacementstring")
                                
                                $string2replace= "output \| ConvertFrom-Json \| convertto-csv -NoTypeInformation"
                                $replacementstring= "output | ConvertFrom-Json"
                                $actioncode= $actioncode-replace("$string2replace","$replacementstring")

                                if ($loglocal -eq 2){
                                    $actioncode= "$actioncode" + 'write-output "Results are stored in the event logs on this host"'
                                }

                                if ($loglocal -eq 3){
                                    $actioncode= "$actioncode" + '$content | ConvertTo-Csv -NoTypeInformation'
                                }

                                $actioncode = [scriptblock]::Create($actioncode)
                            }
                            
                            if ($loglocal -eq 1){                            
                                $actioncode= $actioncode-replace('Export-ModuleMember -Function ','')
                                $actioncode = [scriptblock]::Create($actioncode)
                                Remove-Module -name $action
                            }
                                

                            if ($listofips -eq "localhost"){ 
                                start-job -ScriptBlock $actioncode -name "localhost-$action-$date"
                            }

                            if ($listofips -ne "localhost"){
                                invoke-command -ScriptBlock $actioncode -ComputerName $ip -Credential $credentials -JobName "$ip-$action-$date" -AsJob 
                            }
                        }
                    }                
                }
            }           
            #clear-host
            write-output "All done."
            remove-variable -name action -Scope global -force -ErrorAction SilentlyContinue
        }    
    }

set-location $env:userprofile\desktop\thegreaterwall\results

}

tgw            
