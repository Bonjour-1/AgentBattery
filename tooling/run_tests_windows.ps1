$ErrorActionPreference = 'Stop'
$project = 'E:\Data\Hermes File\projects\AgentBattery'
$flutter = 'C:\ProgramData\flutter\bin\flutter.bat'
$cmd = "set `"PATH=%WINDIR%\System32;%WINDIR%;%WINDIR%\System32\WindowsPowerShell\v1.0;C:\ProgramData\flutter\bin\mingit\cmd;%PATH%`" && cd /d `"$project`" && call `"$flutter`" test"
& "$env:WINDIR\System32\cmd.exe" /d /s /c $cmd
exit $LASTEXITCODE
