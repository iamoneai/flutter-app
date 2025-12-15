# IAMONEAI CLI Quick Setup
# Run: .\iamoneai-cli-setup.ps1

Write-Host "`n🧠 IAMONEAI CLI Setup" -ForegroundColor Cyan
Write-Host "=" * 40 -ForegroundColor DarkGray

# Set project directory
$projectDir = "C:\Users\MP\.claude-worktrees\flutter-app\quirky-lamarr"
Set-Location $projectDir
Write-Host "📁 Directory: $projectDir" -ForegroundColor Green

# Set Firebase project
firebase use app-iamoneai-c36ec 2>$null
Write-Host "🔥 Firebase: app-iamoneai-c36ec" -ForegroundColor Yellow

# Set gcloud project
gcloud config set project app-iamoneai-c36ec 2>$null
Write-Host "☁️  GCloud: app-iamoneai-c36ec" -ForegroundColor Blue

# Store token for API calls
$env:GCLOUD_TOKEN = gcloud auth print-access-token
Write-Host "🔑 Token: Ready (use `$env:GCLOUD_TOKEN)" -ForegroundColor Magenta

Write-Host "`n" + "=" * 40 -ForegroundColor DarkGray
Write-Host "Quick Commands:" -ForegroundColor White
Write-Host "  firebase firestore:indexes" -ForegroundColor Gray
Write-Host "  firebase functions:list" -ForegroundColor Gray
Write-Host "  firebase functions:log -n 20" -ForegroundColor Gray
Write-Host "  gcloud firestore documents list --collection-ids=admin" -ForegroundColor Gray
Write-Host "`n✅ Ready!" -ForegroundColor Green
