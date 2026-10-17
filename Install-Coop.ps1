# Windows PowerShell 5.1. Runs without admin, Python, Git, or build tools.
param(
    [string]$InstallPath,
    [ValidatePattern('^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?$')][string]$Repository,
    [string]$ReleasePath,
    [switch]$NoShortcut
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Save-Json([string]$Path,$Value) {
    [IO.File]::WriteAllText("$Path.new",($Value | ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath "$Path.new" -Destination $Path -Force
}
function Checked-Path([string]$Relative) {
    # Release payloads may never target personal saves, game images, or workspace paths.
    if ($Relative -notmatch '^(bin/|scripts/|seeds/|dolphin/|Load/outfit|kit\.json$|world\.json$|textures\.json$|disc-overlay\.gz$|disc-upgrade\.gz$|COOP-SETUP\.md$|QUICK-START\.txt$|Host-Dungeon\.bat$|Join-Dungeon\.bat$|Update-Coop\.bat$|Add-HD-Textures\.bat$|Configure-Coop-Controls\.bat$)' -or
        $Relative -match '(^|/)(\.|\.\.)(/|$)|[\\:]|^/|//$') { throw "Unsafe release path: $Relative" }
    $path=[IO.Path]::GetFullPath((Join-Path $InstallPath $Relative))
    if (!$path.StartsWith($InstallPath+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw "Path leaves install folder: $Relative" }
    for ($p=$path; $p -and $p.Length -ge $InstallPath.Length; $p=Split-Path $p -Parent) {
        if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Choose a real folder, without directory links: $p" }
    }
    $path
}
function Fetch([string]$Name,[string]$Destination,[long]$Bytes,[string]$Sha) {
    if ((Test-Path -LiteralPath $Destination) -and (Get-Item -LiteralPath $Destination).Length -eq $Bytes -and (Hash $Destination) -eq $Sha) { return }
    $partial="$Destination.partial"
    Write-Host ("Downloading {0} ({1:N1} MB)..." -f $Name,($Bytes/1MB))
    if ($ReleasePath) { [IO.File]::Copy((Join-Path $ReleasePath $Name),$partial,$true) }
    else {
        $url="$assetBase/$Name"
        $curl=Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curl) {
            & $curl.Source --fail --location --retry 3 --retry-delay 2 --continue-at - --output $partial $url
            if ($LASTEXITCODE) { throw 'Download interrupted. Run this same installer again to resume.' }
        } else { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $partial }
    }
    if ((Get-Item -LiteralPath $partial).Length -ne $Bytes -or (Hash $partial) -ne $Sha) {
        Remove-Item -LiteralPath $partial -Force
        throw "Download verification failed for $Name. Run the installer again."
    }
    Move-Item -LiteralPath $partial -Destination $Destination -Force
}
function Restore-Transaction {
    if (!(Test-Path -LiteralPath $journal)) { return }
    Write-Host 'Recovering an interrupted update...'
    foreach ($file in (Json $journal).files) {
        $dest=Checked-Path $file.path
        if ($file.existed) { [IO.File]::Copy((Join-Path $backup $file.path),$dest,$true) }
        elseif (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
    }
    Remove-Item -LiteralPath $journal -Force
}

if (!$InstallPath) { $InstallPath=Join-Path $env:USERPROFILE 'Games/Wind-Waker-Coop' }
$InstallPath=[IO.Path]::GetFullPath($InstallPath).TrimEnd('\','/')
if ([IO.Path]::GetPathRoot($InstallPath).TrimEnd('\','/') -eq $InstallPath) { throw 'Choose a game folder, not a drive root.' }
if (Test-Path -LiteralPath (Join-Path $InstallPath 'workspace.json')) { throw 'This is a developer workspace kit. Use a separate install folder for the friend installer.' }
$installed=Join-Path $InstallPath 'installed-release.json'
if (Test-Path -LiteralPath $installed) {
    $previous=Json $installed
    if (!$Repository) { $Repository=$previous.repository }
    if (!$Repository -and !$ReleasePath -and $previous.PSObject.Properties.Name -contains 'releasePath') { $ReleasePath=$previous.releasePath }
}
if (!$Repository -and !$ReleasePath) { throw 'No GitHub download is configured yet. Use the extracted setup ZIP, or supply -Repository your-account/your-repo.' }
New-Item -ItemType Directory -Force -Path $InstallPath | Out-Null
$cache=Join-Path $InstallPath '.coop-update'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
if ((Get-Item -LiteralPath $InstallPath).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Choose a folder without directory links.' }
foreach ($folder in @($cache,(Join-Path $InstallPath 'play'))) {
    if ((Test-Path -LiteralPath $folder) -and ((Get-Item -LiteralPath $folder).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Directory link is not supported: $folder" }
}
$locks=@(); $heldFiles=@(); $archives=@()
$backup=Join-Path $cache 'backup'; $journal=Join-Path $cache 'transaction.json'
try {
    foreach ($name in @('install.lock','host.lock','join.lock')) {
        $parent=if ($name -eq 'install.lock') {$cache} else {Join-Path $InstallPath 'play'}
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        try { $locks+=,[IO.File]::Open((Join-Path $parent $name),'OpenOrCreate','ReadWrite','None') }
        catch { throw 'Close both games and launchers before installing or updating.' }
    }
    # An externally launched Dolphin also holds its executable; fail before modifying anything.
    foreach ($name in @('bin/ww-multiplayer.exe','dolphin/Dolphin.exe')) {
        $path=Checked-Path $name
        if (Test-Path -LiteralPath $path) {
            try { $heldFiles+=,[IO.File]::Open($path,'Open','ReadWrite','None') }
            catch { throw 'Close Dolphin and the multiplayer helper, then retry.' }
        }
    }
    foreach ($file in $heldFiles) {$file.Dispose()}; $heldFiles=@()
    Restore-Transaction
    $manifestPath=Join-Path $cache 'release.json'
    if ($ReleasePath) { [IO.File]::Copy((Join-Path $ReleasePath 'coop-release.json'),$manifestPath,$true) }
    else {
        $assetBase="https://github.com/$Repository/releases/latest/download"
        Invoke-WebRequest -UseBasicParsing -Uri "$assetBase/coop-release.json" -OutFile $manifestPath
    }
    $release=Json $manifestPath
    if ($release.format -ne 1 -or $release.components.Count -ne 2) { throw 'Unsupported download manifest.' }
    if (!$Repository -and $release.repository) { $Repository=$release.repository }
    if (!$ReleasePath) {
        if ($release.tag -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Invalid release version.' }
        # Freeze the release during download, even if a newer release appears meanwhile.
        $assetBase="https://github.com/$Repository/releases/download/$($release.tag)"
    }
    $changes=@(); $seen=@{}
    foreach ($component in $release.components) {
        if ($component.name -notin @('core','dolphin') -or $component.asset -cne "coop-$($component.name).zip" -or
            $component.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $component.bytes -lt 1 -or $component.bytes -gt 300MB -or
            @($component.files).Count -lt 1 -or @($component.files).Count -gt 3000) { throw 'Invalid release component.' }
        $pending=@()
        foreach ($file in $component.files) {
            $dest=Checked-Path $file.path
            if ($seen.ContainsKey($file.path)) { throw "Repeated release path: $($file.path)" }
            $seen[$file.path]=$true
            if ($file.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $file.bytes -lt 0 -or $file.bytes -gt 300MB) { throw 'Invalid file metadata.' }
            if (!(Test-Path -LiteralPath $dest) -or (Get-Item -LiteralPath $dest).Length -ne $file.bytes -or (Hash $dest) -ne $file.sha256) { $pending+=,$file }
        }
        if (!$pending.Count) { Write-Host "$($component.name): already up to date; no download."; continue }
        $zipPath=Join-Path $cache $component.asset
        Fetch $component.asset $zipPath $component.bytes $component.sha256
        $zip=[IO.Compression.ZipFile]::OpenRead($zipPath); $archives+=,$zip
        if ($zip.Entries.Count -ne $component.files.Count) { throw 'Unexpected archive entries.' }
        $entries=@{}
        foreach ($entry in $zip.Entries) {
            $null=Checked-Path $entry.FullName
            if ($entries.ContainsKey($entry.FullName)) { throw 'Repeated archive entry.' }
            $entries[$entry.FullName]=$entry
        }
        foreach ($file in $component.files) {
            if (!$entries.ContainsKey($file.path) -or $entries[$file.path].Length -ne $file.bytes) { throw "Archive is incomplete: $($file.path)" }
        }
        foreach ($file in $pending) {
            $staged=Join-Path (Join-Path $cache 'staged') $file.path
            New-Item -ItemType Directory -Force -Path (Split-Path $staged -Parent) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[$file.path],$staged,$true)
            if ((Hash $staged) -ne $file.sha256) { throw "File verification failed: $($file.path)" }
            $changes+=,@{path=$file.path;existed=(Test-Path -LiteralPath (Checked-Path $file.path))}
        }
    }
    # Download and validate every changed component before touching the installed version.
    foreach ($file in $changes) {
        if ($file.existed) {
            $saved=Join-Path $backup $file.path
            New-Item -ItemType Directory -Force -Path (Split-Path $saved -Parent) | Out-Null
            [IO.File]::Copy((Checked-Path $file.path),$saved,$true)
        }
    }
    if ($changes.Count) {
        Save-Json $journal @{files=@($changes)}
        try {
            foreach ($file in $changes) {
                $dest=Checked-Path $file.path
                New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
                [IO.File]::Copy((Join-Path (Join-Path $cache 'staged') $file.path),$dest,$true)
            }
            Remove-Item -LiteralPath $journal -Force
        } catch { Restore-Transaction; throw }
    }
    Save-Json $installed @{format=1;version=$release.version;repository=$Repository;tag=$release.tag;releasePath=$ReleasePath}
    if (!$NoShortcut) {
        $shell=New-Object -ComObject WScript.Shell
        $shortcut=$shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Wind Waker - Join.lnk'))
        $shortcut.TargetPath=Join-Path $InstallPath 'Join-Dungeon.bat'; $shortcut.WorkingDirectory=$InstallPath
        $shortcut.Save()
    }
    Write-Host "`nReady! Open Join-Dungeon.bat in $InstallPath"
    Write-Host 'First play: connect Tailscale, choose your own clean USA ISO, and enter the host address.'
    Write-Host 'Later: double-click Update-Coop.bat. Saves and optional HD textures stay in place.'
} finally {
    foreach ($item in @($archives)+@($heldFiles)+@($locks)) { $item.Dispose() }
    # Only explicitly owned small staging/backup files; keep verified ZIPs for retry/offline repair.
    if (!(Test-Path -LiteralPath $journal)) {
        foreach ($part in @('staged','backup')) {
            $owned=[IO.Path]::GetFullPath((Join-Path $cache $part))
            if ($owned.StartsWith($InstallPath+'\',[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $owned)) {
                Remove-Item -LiteralPath $owned -Recurse -Force
            }
        }
    }
}
