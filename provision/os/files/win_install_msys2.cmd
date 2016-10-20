@setlocal EnableDelayedExpansion EnableExtensions
@for %%i in (%~dp0\_packer_config*.cmd) do @call "%%~i"
@if defined PACKER_DEBUG (@echo on) else (@echo off)

if not defined MSYS2_ARCH (
  reg Query "HKLM\Hardware\Description\System\CentralProcessor\0" | find /i "x86" > NUL && (set MSYS2_ARCH=i686) || (set MSYS2_ARCH=x86_64)
)
if not defined MSYS2_VERSION set MSYS2_VERSION=20160205
if not defined MSYS2_HOME set MSYS2_HOME=%SystemDrive%\msys2
if not defined MSYS2_URL set MSYS2_URL=http://repo.msys2.org/distrib/%MSYS2_ARCH%/msys2-%MSYS2_ARCH%-%MSYS2_VERSION%.exe

if not defined MSYS2_INSTALL_SCRIPT set MSYS2_INSTALL_SCRIPT=%~dp0\win_install_msys2.js
if not defined MSYS2_INIT_SCRIPT set MSYS2_INIT_SCRIPT=%~dp0\win_init_msys2.sh
if "%MSYS2_ARCH%" == "x86_64" (set MSYSTEM=MINGW64) else (set MSYSTEM=MINGW32)

wmic os get version | findstr "5.1" >nul
if not errorlevel 1 (set WIN_XP=1) else (set WIN_XP=0)

for %%i in ("%MSYS2_URL%") do set MSYS2_EXE=%%~nxi
set MSYS2_TEMP_DIR=%TEMP%\msys2
set MSYS2_TEMP_PATH=%MSYS2_TEMP_DIR%\%MSYS2_EXE%

echo ==^> Creating "%MSYS2_TEMP_DIR%"
mkdir "%MSYS2_TEMP_DIR%"
pushd "%MSYS2_TEMP_DIR%"

echo ==^> Blocking SSH port 22 on the firewall
if "%WIN_XP%" == "1" (
    netsh firewall add allowedprogram name="sshd" mode="DISABLE" program="%MSYS2_HOME%\usr\bin\sshd.exe" scope="ALL" profile="ALL"
    netsh firewall add portopening name="ssh" mode="DISABLE" protocol=TCP port=22 scope="ALL" profile="ALL"
) else (
    netsh advfirewall firewall add rule name="sshd" dir=in action=block program="%MSYS2_HOME%\usr\bin\sshd.exe" enable=yes
    netsh advfirewall firewall add rule name="ssh" dir=in action=block protocol=TCP localport=22
)

if exist "%MSYS2_HOME%\components.xml" (
    echo ==^> MSYS2 already installed in "%MSYS2_HOME%"
    goto installed_ok
)

if exist "%SystemRoot%\_download.cmd" (
    call "%SystemRoot%\_download.cmd" "%MSYS2_URL%" "%MSYS2_TEMP_PATH%"
) else (
    echo ==^> Downloading "%MSYS2_URL%" to "%MSYS2_TEMP_PATH%"
    powershell -Command "(New-Object System.Net.WebClient).DownloadFile('%MSYS2_URL%', '%MSYS2_TEMP_PATH%')" <NUL
)
if errorlevel 1 goto exit1

echo ==^> Installing MSYS2

if not exist "%MSYS2_INSTALL_SCRIPT%" echo ==^> ERROR: File not found: "%MSYS2_INSTALL_SCRIPT%" & goto exit1

@rem WARNING: Do not use -v (verbose), otherwise the installer will get stuck on "SHOW FINISHED PAGE" page
"%MSYS2_TEMP_PATH%" --platform minimal --script "%MSYS2_INSTALL_SCRIPT%"

if errorlevel 1 (
    echo ==^> The installation failed and returned error %ERRORLEVEL%.
    goto exit1
)

:installed_ok
if not exist "%MSYS2_INIT_SCRIPT%" echo ==^> ERROR: File not found: "%MSYS2_INIT_SCRIPT%" & goto exit1

echo ==^> Running "%MSYS2_INIT_SCRIPT%"
"%MSYS2_HOME%\usr\bin\bash.exe" --login -c ". '%MSYS2_INIT_SCRIPT%'"
if errorlevel 1 goto exit1

popd

echo ==^> Unblocking SSH port 22 on the firewall
if "%WIN_XP%" == "1" (
    netsh firewall delete allowedprogram program="%MSYS2_HOME%\usr\bin\sshd.exe" profile="ALL"
    netsh firewall delete portopening protocol=TCP port=22 profile="ALL"
) else (
    netsh advfirewall firewall delete rule name="sshd"
    netsh advfirewall firewall delete rule name="ssh"
)

echo ==^> Opening SSH port 22 on the firewall
if "%WIN_XP%" == "1" (
    netsh firewall add allowedprogram name="sshd" mode="ENABLE" program="%MSYS2_HOME%\usr\bin\sshd.exe" scope="ALL" profile="ALL"
    netsh firewall add portopening name="ssh" mode="ENABLE" protocol=TCP port=22 scope="ALL" profile="ALL"
) else (
    netsh advfirewall firewall add rule name="sshd" dir=in action=allow program="%MSYS2_HOME%\usr\bin\sshd.exe" enable=yes
    netsh advfirewall firewall add rule name="ssh" dir=in action=allow protocol=TCP localport=22
)

:exit0

ver>nul

goto :exit

:exit1

verify other 2>nul

:exit
