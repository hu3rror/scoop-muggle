if (Test-Path "$PSScriptRoot\app\bin\python-lib.bypy.frozen") {
    Rename-Item -Path "$PSScriptRoot\app\bin\python-lib.bypy.frozen" -NewName "python-lib.bypy.frozen.orig"
}

Write-Host "$version"
$FILE_URL = "https://github.com/Cirn09/calibre-do-not-translate-my-path/releases/download/v$version/patch-win-$version.zip"
$OUTPUT_FILE = "patch-win-$version.zip"
Invoke-WebRequest -Uri $FILE_URL -OutFile "$PSScriptRoot\$OUTPUT_FILE"
Expand-ZipArchive "$PSScriptRoot\$OUTPUT_FILE" "$dir" -Removal -ExtractDir "Calibre2\app\bin"
Move-Item -Path "$PSScriptRoot\python-lib.bypy.frozen" -Destination "$PSScriptRoot\app\bin\python-lib.bypy.frozen"
Write-Host "Patch is OK"
