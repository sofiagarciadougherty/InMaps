# Kill any process using port 8081 (Metro)
Write-Host "🔄 Checking for Metro running on port 8081..."
$port = 8081
$pid = netstat -ano | Select-String ":$port" | ForEach-Object {
    ($_ -split '\s+')[-1]
} | Select-Object -First 1

if ($pid) {
    Write-Host "🚫 Killing process on port $port (PID: $pid)..."
    taskkill /F /PID $pid
} else {
    Write-Host "✅ No existing process on port $port"
}

# Start Metro with reset cache
Start-Process powershell -ArgumentList "npx react-native start --reset-cache" -NoNewWindow

Start-Sleep -Seconds 5

# Launch Android app
Write-Host "🚀 Launching Android app..."
npx react-native run-android
