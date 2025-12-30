# iKVM Launcher - Run ATEN Java iKVM from JNLP files
# Bypasses Java Web Start security issues

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Xml

$ErrorActionPreference = "Stop"

# File picker dialog
function Select-JnlpFile {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select JNLP File"
    $dialog.Filter = "JNLP Files (*.jnlp)|*.jnlp|All Files (*.*)|*.*"
    $dialog.InitialDirectory = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

# Parse JNLP file
function Parse-Jnlp {
    param([string]$Path)

    [xml]$jnlp = Get-Content $Path

    $codebase = $jnlp.jnlp.codebase
    $mainClass = $jnlp.jnlp.'application-desc'.'main-class'
    $arguments = @($jnlp.jnlp.'application-desc'.argument)

    # Get JAR names
    $mainJar = $jnlp.jnlp.resources | Where-Object { $_.jar } | ForEach-Object { $_.jar.href } | Select-Object -First 1

    # Get Windows x64 native lib
    $nativeLib = $jnlp.jnlp.resources | Where-Object { $_.os -eq "Windows" -and ($_.arch -eq "amd64" -or $_.arch -eq "x86_64") } |
                 ForEach-Object { $_.nativelib.href } | Select-Object -First 1

    return @{
        Codebase = $codebase
        MainClass = $mainClass
        Arguments = $arguments
        MainJar = $mainJar
        NativeLib = $nativeLib
    }
}

# Download file ignoring SSL errors
function Download-File {
    param([string]$Url, [string]$OutFile)

    # Ignore SSL certificate errors for self-signed IPMI certs
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($Url, $OutFile)
}

# Main
Write-Host "=== iKVM Launcher ===" -ForegroundColor Cyan
Write-Host ""

# Select JNLP file
$jnlpPath = Select-JnlpFile
if (-not $jnlpPath) {
    Write-Host "No file selected. Exiting." -ForegroundColor Yellow
    exit
}

Write-Host "Selected: $jnlpPath" -ForegroundColor Green

# Parse JNLP
Write-Host "Parsing JNLP..." -ForegroundColor Cyan
$config = Parse-Jnlp -Path $jnlpPath

Write-Host "  Codebase: $($config.Codebase)"
Write-Host "  Main JAR: $($config.MainJar)"
Write-Host "  Native Lib: $($config.NativeLib)"
Write-Host "  Main Class: $($config.MainClass)"
Write-Host ""

# Setup working directory
$workDir = Join-Path $env:TEMP "ikvm_launcher"
if (-not (Test-Path $workDir)) {
    New-Item -ItemType Directory -Path $workDir | Out-Null
}

# Find Java
$javaHome = Get-ChildItem "C:\Program Files\Java" -Directory |
            Where-Object { $_.Name -like "jre*" -or $_.Name -like "jdk*" } |
            Sort-Object Name -Descending | Select-Object -First 1

if (-not $javaHome) {
    $javaHome = Get-ChildItem "C:\Program Files (x86)\Java" -Directory |
                Where-Object { $_.Name -like "jre*" -or $_.Name -like "jdk*" } |
                Sort-Object Name -Descending | Select-Object -First 1
}

if (-not $javaHome) {
    Write-Host "ERROR: Java not found. Please install Java 8." -ForegroundColor Red
    pause
    exit 1
}

$javaBin = Join-Path $javaHome.FullName "bin"
Write-Host "Using Java: $($javaHome.FullName)" -ForegroundColor Green

# Download packed JARs
Write-Host "Downloading JARs..." -ForegroundColor Cyan

$mainJarPacked = Join-Path $workDir "main.jar.pack.gz"
$mainJarUrl = "$($config.Codebase)$($config.MainJar).pack.gz"
Write-Host "  Downloading $mainJarUrl"
Download-File -Url $mainJarUrl -OutFile $mainJarPacked

$nativeJarPacked = Join-Path $workDir "native.jar.pack.gz"
$nativeJarUrl = "$($config.Codebase)$($config.NativeLib).pack.gz"
Write-Host "  Downloading $nativeJarUrl"
Download-File -Url $nativeJarUrl -OutFile $nativeJarPacked

# Unpack JARs
Write-Host "Unpacking JARs..." -ForegroundColor Cyan

$mainJar = Join-Path $workDir "iKVM.jar"
$nativeJar = Join-Path $workDir "native.jar"

$unpack200 = Join-Path $javaBin "unpack200.exe"
& $unpack200 $mainJarPacked $mainJar
& $unpack200 $nativeJarPacked $nativeJar

# Extract native DLLs (rename to .zip since Expand-Archive requires it)
Write-Host "Extracting native libraries..." -ForegroundColor Cyan
$nativeZip = Join-Path $workDir "native.zip"
Copy-Item $nativeJar $nativeZip -Force
Expand-Archive -Path $nativeZip -DestinationPath $workDir -Force

# Run iKVM
Write-Host ""
Write-Host "Launching iKVM..." -ForegroundColor Green
Write-Host ""

$java = Join-Path $javaBin "javaw.exe"
$args = @(
    "-Djava.library.path=$workDir",
    "-cp", $mainJar,
    $config.MainClass
) + $config.Arguments

Write-Host "Command: java $($args -join ' ')" -ForegroundColor DarkGray
Write-Host ""

Start-Process -FilePath $java -ArgumentList $args -WorkingDirectory $workDir

Write-Host "iKVM launched successfully!" -ForegroundColor Green
Start-Sleep -Seconds 2
