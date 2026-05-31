@echo off
echo ==========================================
echo   WaVoIP Bridge Server - Setup Windows
echo ==========================================
echo.

REM Check Node.js
node --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERRO: Node.js nao encontrado!
    echo Baixe em: https://nodejs.org/
    echo Instale a versao LTS (18 ou 20)
    pause
    exit /b 1
)

echo Node.js: OK
node --version

REM Check wavoip.node
if not exist wavoip.node (
    echo ERRO: wavoip.node nao encontrado!
    echo Coloque wavoip.node na mesma pasta deste script.
    pause
    exit /b 1
)

echo wavoip.node: OK

echo.
echo ==========================================
echo   Iniciando servidor na porta 3500...
echo ==========================================
echo.
echo Depois de iniciar, rode em OUTRO terminal:
echo   npx localtunnel --port 3500
echo.
echo Ou instale ngrok e rode:
echo   ngrok http 3500
echo.
echo O URL do tunnel sera usado no Mac.
echo ==========================================
echo.

node bridge-server.js

pause
