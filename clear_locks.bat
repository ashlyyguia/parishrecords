@echo off
echo 🔧 Clearing Hive lock files...

echo ⏹️ Stopping processes...
taskkill /F /IM flutter.exe >nul 2>&1
taskkill /F /IM parishrecord.exe >nul 2>&1

echo 🧹 Clearing lock files...
del "%USERPROFILE%\Documents\*.lock" >nul 2>&1

echo 🧹 Clearing Flutter cache...
flutter clean >nul 2>&1

echo ✅ Cleanup completed!
echo 💡 You can now run 'flutter run' safely
pause
