@echo off
echo ==========================================
echo   WaVoIP Bridge Server - Setup Windows
echo ==========================================
echo.

REM Check if electron exists
if exist electron\electron.exe (
    echo Electron: OK
    goto :start
)

echo Baixando Electron 12.2.3...
echo (necessario para wavoip.node)
echo.

REM Check if Node exists for npx
node --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Node.js nao encontrado. Baixando Electron manualmente...

    REM Try PowerShell download
    powershell -Command "Invoke-WebRequest -Uri 'https://registry.npmmirror.com/-/binary/electron/12.2.3/electron-v12.2.3-win32-x64.zip' -OutFile 'electron.zip'"

    if not exist electron.zip (
        echo ERRO: Nao conseguiu baixar Electron.
        echo Baixe manualmente: https://registry.npmmirror.com/-/binary/electron/12.2.3/electron-v12.2.3-win32-x64.zip
        echo Extraia para a pasta 'electron' aqui.
        pause
        exit /b 1
    )

    echo Extraindo...
    powershell -Command "Expand-Archive -Path 'electron.zip' -DestinationPath 'electron' -Force"
    del electron.zip
    echo Electron extraido!
) else (
    echo Usando Node para baixar Electron...
    mkdir electron 2>nul
    npx --yes electron-download --version=12.2.3 --platform=win32 --arch=x64 2>nul

    REM Fallback: PowerShell
    if not exist electron\electron.exe (
        powershell -Command "Invoke-WebRequest -Uri 'https://registry.npmmirror.com/-/binary/electron/12.2.3/electron-v12.2.3-win32-x64.zip' -OutFile 'electron.zip'"
        powershell -Command "Expand-Archive -Path 'electron.zip' -DestinationPath 'electron' -Force"
        del electron.zip 2>nul
    )
)

if not exist electron\electron.exe (
    echo ERRO: electron.exe nao encontrado!
    pause
    exit /b 1
)

:start
echo.
echo Verificando wavoip.node...
if not exist wavoip.node (
    echo ERRO: wavoip.node nao encontrado!
    echo Coloque wavoip.node nesta pasta.
    pause
    exit /b 1
)
echo wavoip.node: OK

echo.
echo ==========================================
echo   Iniciando servidor na porta 3500...
echo ==========================================
echo.

set ELECTRON_RUN_AS_NODE=1
electron\electron.exe bridge-server.js

echo.
echo Servidor encerrado.
pause
