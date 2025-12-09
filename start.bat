@echo off
REM Docker container startup script for APIOK API Gateway
REM This script builds and runs the Docker container with proper port mapping

setlocal enabledelayedexpansion

REM Configuration
set IMAGE_NAME=apiok
set CONTAINER_NAME=apiok

REM Generate version based on current date and time (YYYYMMDDHHMMSS)
set "YYYY=%date:~0,4%"
set "MM=%date:~5,2%"
set "DD=%date:~8,2%"
set "HH=%time:~0,2%"
set "NN=%time:~3,2%"
set "SS=%time:~6,2%"
REM Remove spaces from time values
set "HH=%HH: =0%"
set "NN=%NN: =0%"
set "SS=%SS: =0%"
set "VERSION=%YYYY%%MM%%DD%%HH%%NN%%SS%"

REM Check if Docker is running
docker version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Docker is not running or not installed!
    echo Please start Docker Desktop and try again.
    pause
    exit /b 1
)

REM Check if container already exists
docker ps -a --filter "name=%CONTAINER_NAME%" --format "{{.Names}}" | findstr /C:"%CONTAINER_NAME%" >nul
if not errorlevel 1 (
    echo Container %CONTAINER_NAME% already exists.
    echo Stopping existing container...
    docker stop %CONTAINER_NAME% >nul 2>&1
    echo Removing existing container...
    docker rm %CONTAINER_NAME% >nul 2>&1
)

REM Build the Docker image
echo.
echo ========================================
echo Building Docker image: %IMAGE_NAME%
echo ========================================
echo.

docker build -t %IMAGE_NAME%:%VERSION% .
if errorlevel 1 (
    echo.
    echo ERROR: Docker build failed!
    pause
    exit /b 1
)

REM Tag as latest
docker tag %IMAGE_NAME%:%VERSION% %IMAGE_NAME%:latest

echo.
echo ========================================
echo Starting container: %CONTAINER_NAME%
echo ========================================
echo.
echo Port mappings:
echo   - Host port 80   -^> Container port 80   ^(HTTP API Gateway^)
echo   - Host port 443  -^> Container port 443  ^(HTTPS API Gateway^)
echo   - Host port 8080 -^> Container port 8080 ^(Admin API ^& Dashboard^)
echo.

REM Ensure we're in the script directory
cd /d "%~dp0"


docker run -d ^
    --name %CONTAINER_NAME% ^
    -p 80:80 ^
    -p 443:443 ^
    -p 8080:8080 ^
    --restart unless-stopped ^
    %IMAGE_NAME%:latest

if errorlevel 1 (
    echo.
    echo ERROR: Failed to start container!
    pause
    exit /b 1
)

echo.
echo ========================================
echo Container started successfully!
echo ========================================
echo.
echo Container name: %CONTAINER_NAME%
echo Image: %IMAGE_NAME%:latest
echo.

REM Show container status
docker ps --filter "name=%CONTAINER_NAME%" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo.
echo Waiting for nginx to start...
timeout /t 2 /nobreak >nul

REM Check if container is running
docker ps --filter "name=%CONTAINER_NAME%" --format "{{.Names}}" | findstr /C:"%CONTAINER_NAME%" >nul
if errorlevel 1 (
    echo.
    echo ========================================
    echo WARNING: Container may have stopped!
    echo ========================================
    echo.
    echo Showing container logs:
    echo ----------------------------------------
    docker logs %CONTAINER_NAME%
    echo ----------------------------------------
    echo.
    echo Container exited. Check the logs above for errors.
) else (
    echo.
    echo ========================================
    echo Container is running!
    echo ========================================
    echo.
    echo Showing recent logs (last 50 lines):
    echo ----------------------------------------
    docker logs --tail 50 %CONTAINER_NAME%
    echo ----------------------------------------
    echo.
    echo You can access the service at:
    echo   - http://localhost         ^(API Gateway^)
    echo   - https://localhost        ^(API Gateway HTTPS^)
    echo   - http://localhost^:8080    ^(Admin API ^& Dashboard^)
    echo.
    echo To view real-time logs: docker logs -f %CONTAINER_NAME%
    echo To stop: docker stop %CONTAINER_NAME%
    echo To remove: docker rm %CONTAINER_NAME%
)

echo.
pause

