$ErrorActionPreference = 'Stop'
$vsdev = 'C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat'
$project = 'E:\Data\Hermes File\projects\AgentBattery'
$flutter = 'C:\ProgramData\flutter\bin\flutter.bat'
$cmd = "set `"PATH=%WINDIR%\System32;%WINDIR%;%WINDIR%\System32\WindowsPowerShell\v1.0;C:\ProgramData\flutter\bin\mingit\cmd;%PATH%`" && call `"$vsdev`" -arch=x64 -host_arch=x64 && cd /d `"$project`" && call `"$flutter`" build windows --release"
& "$env:WINDIR\System32\cmd.exe" /d /s /c $cmd
exit $LASTEXITCODE
