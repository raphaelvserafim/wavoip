@echo off
echo ==========================================
echo   Ativando SSH no Windows (metodo 2)
echo ==========================================
echo.
echo Execute como ADMINISTRADOR!
echo.

REM Tentar iniciar direto (pode ja estar instalado)
net start sshd 2>nul
if %errorlevel% equ 0 (
    echo SSH ja estava instalado! Servico iniciado.
    goto :info
)

REM Tentar via sc
sc start sshd 2>nul
if %errorlevel% equ 0 (
    echo SSH iniciado via sc!
    goto :info
)

REM Tentar instalar via DISM (mais rapido que PowerShell)
echo Instalando via DISM...
dism /Online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 /NoRestart

echo Iniciando servico...
net start sshd
sc config sshd start=auto

REM Firewall
netsh advfirewall firewall add rule name="SSH" dir=in action=allow protocol=TCP localport=22 2>nul

:info
echo.
echo ==========================================
echo   Informacoes de conexao:
echo ==========================================
echo.
echo IP:
ipconfig | findstr /i "IPv4"
echo.
echo Usuario:
whoami
echo.
echo No Mac rode:
echo   ssh USUARIO@IP
echo.
pause
