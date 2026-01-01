@echo off
echo ========================================
echo ANDROID LICENSE FIX SCRIPT
echo ========================================
echo.

REM Check if Android SDK exists
if not exist "D:\Android" (
    echo ERROR: Android SDK not found at D:\Android
    echo Please install Android Studio first
    pause
    exit /b 1
)

echo Step 1: Finding sdkmanager...
echo.

REM Try different possible locations
set SDKMANAGER=""

if exist "D:\Android\cmdline-tools\latest\bin\sdkmanager.bat" (
    set SDKMANAGER="D:\Android\cmdline-tools\latest\bin\sdkmanager.bat"
    echo Found: D:\Android\cmdline-tools\latest\bin\sdkmanager.bat
)

if exist "D:\Android\tools\bin\sdkmanager.bat" (
    set SDKMANAGER="D:\Android\tools\bin\sdkmanager.bat"
    echo Found: D:\Android\tools\bin\sdkmanager.bat
)

if %SDKMANAGER%=="" (
    echo.
    echo ERROR: sdkmanager not found!
    echo.
    echo SOLUTION:
    echo 1. Open Android Studio
    echo 2. Go to: File ^> Settings ^> Appearance ^& Behavior ^> System Settings ^> Android SDK
    echo 3. Click "SDK Tools" tab
    echo 4. Check "Android SDK Command-line Tools (latest)"
    echo 5. Click "Apply" and wait for installation
    echo 6. Run this script again
    echo.
    pause
    exit /b 1
)

echo.
echo Step 2: Accepting Android licenses...
echo.
echo You will be asked to accept several licenses.
echo Type 'y' and press Enter for each one.
echo.
pause

REM Accept licenses
%SDKMANAGER% --licenses

echo.
echo ========================================
echo DONE!
echo ========================================
echo.
echo Now you can run: flutter run
echo.
pause
