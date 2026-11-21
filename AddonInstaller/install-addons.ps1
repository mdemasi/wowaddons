# install-addons.ps1 - install/update WoW addons from zips, and back up / restore
# addon data and settings to a private git repo (Windows version of install-addons.sh).
#
#   install-addons.bat                 back up addon data, then install every .zip next to this script
#   install-addons.bat -NoBackup       install without backing up first
#   install-addons.bat backup          back up addon data and settings, commit, push
#   install-addons.bat list            show recent backups
#   install-addons.bat restore [id]    put the latest backup (or a listed id) back into WTF
#   install-addons.bat pull            download the latest backup and copy it into WTF (same as restore)
#
# Backups need Git for Windows (https://git-scm.com). Its credential manager handles the
# GitHub login in your browser the first time you push.

param(
    [string]$Command = '',
    [string]$Id = '',
    [switch]$NoBackup
)

# Optional settings (otherwise found/asked once and remembered in .txt files here):
$AddOnsPath   = ''   # e.g. 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns'
$BackupRemote = ''   # e.g. 'https://github.com/YOU/wowaddons-backup.git'  (make the repo PRIVATE)

$ErrorActionPreference = 'Stop'
$Here       = $PSScriptRoot
$PathFile   = Join-Path $Here 'addons-path.txt'
$RemoteFile = Join-Path $Here 'backup-remote.txt'
$Repo       = Join-Path $Here 'backup-repo'

function Say-Red($t)   { Write-Host $t -ForegroundColor Red }
function Say-Green($t) { Write-Host $t -ForegroundColor Green }
function Fail($t)      { Say-Red $t; exit 1 }

# Run git in the backup repo. Returns the exit code; output goes to the console.
function Git-Run {
    $ErrorActionPreference = 'Continue'
    & git -C $Repo @args | Out-Host
    return $LASTEXITCODE
}
# Run git in the backup repo and return its output as text ($null on failure).
function Git-Out {
    $ErrorActionPreference = 'Continue'
    $out = & git -C $Repo @args
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($out -join "`n")
}

# --- locate AddOns / WTF -----------------------------------------------------------
function Find-AddOnsPath {
    $roots = @("${env:ProgramFiles(x86)}\World of Warcraft", "$env:ProgramFiles\World of Warcraft",
               'C:\World of Warcraft', 'D:\World of Warcraft', 'E:\World of Warcraft',
               'C:\Games\World of Warcraft', 'D:\Games\World of Warcraft', 'E:\Games\World of Warcraft')
    $found = @()
    foreach ($r in $roots) {
        if (Test-Path -LiteralPath $r) {
            foreach ($flavor in Get-ChildItem -LiteralPath $r -Directory -Filter '_*_') {
                $p = Join-Path $flavor.FullName 'Interface\AddOns'
                if (Test-Path -LiteralPath $p) { $found += $p }
            }
        }
    }
    if ($found.Count -eq 1) { return $found[0] }
    if ($found.Count -gt 1) {
        Write-Host 'Found more than one AddOns folder:'
        for ($i = 0; $i -lt $found.Count; $i++) { Write-Host "  [$($i + 1)] $($found[$i])" }
        $n = Read-Host 'Which one is WoW Forever? Enter the number'
        if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $found.Count) { return $found[[int]$n - 1] }
    }
    return (Read-Host 'Paste the full path to your WoW Forever Interface\AddOns folder').Trim('"', ' ')
}

if (-not $AddOnsPath -and (Test-Path -LiteralPath $PathFile)) { $AddOnsPath = (Get-Content -LiteralPath $PathFile -Raw).Trim() }
if (-not $AddOnsPath -or -not (Test-Path -LiteralPath $AddOnsPath)) {
    $AddOnsPath = Find-AddOnsPath
    if (-not $AddOnsPath -or -not (Test-Path -LiteralPath $AddOnsPath)) { Fail "AddOns folder not found: '$AddOnsPath'" }
    Set-Content -LiteralPath $PathFile -Value $AddOnsPath
}
$AddOnsPath = (Resolve-Path -LiteralPath $AddOnsPath).Path
$WTF = Join-Path (Split-Path (Split-Path $AddOnsPath -Parent) -Parent) 'WTF'

if (-not $BackupRemote -and (Test-Path -LiteralPath $RemoteFile)) { $BackupRemote = (Get-Content -LiteralPath $RemoteFile -Raw).Trim() }

function Test-GameRunning {
    return [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Wow*' })
}

# --- install ---------------------------------------------------------------------
function Do-Install {
    Write-Host "Installing to: $AddOnsPath`n"
    $zips = @(Get-ChildItem -LiteralPath $Here -Filter '*.zip' -File)
    if ($zips.Count -eq 0) { Write-Host 'No .zip files found next to this script.'; return }

    $installedDir = Join-Path $Here 'installed'
    New-Item -ItemType Directory -Force -Path $installedDir | Out-Null
    $failed = 0

    foreach ($zip in $zips) {
        $tmp = Join-Path $env:TEMP ('addon_' + [guid]::NewGuid())
        try {
            Expand-Archive -LiteralPath $zip.FullName -DestinationPath $tmp -Force

            # An addon folder holds a .toc named after it (Name.toc or Name_Variant.toc).
            $dirs = @(Get-ChildItem -LiteralPath $tmp -Recurse -Filter '*.toc' -File |
                Where-Object { $_.BaseName -eq $_.Directory.Name -or $_.BaseName -like "$($_.Directory.Name)_*" } |
                ForEach-Object { $_.Directory.FullName } | Sort-Object -Unique)
            # Keep only top-level addon folders (skip libraries bundled inside an addon).
            $addons = @($dirs | Where-Object { $d = $_; -not ($dirs | Where-Object { $d -ne $_ -and $d.StartsWith($_ + '\') }) })
            if ($addons.Count -eq 0) { throw 'no addon folder (with a matching .toc) inside' }

            foreach ($src in $addons) {
                $name = Split-Path $src -Leaf
                if (-not $name -or $name -like 'Blizzard_*') { continue }
                $dest = Join-Path $AddOnsPath $name
                $verb = 'Installed'
                if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force; $verb = 'Updated' }
                Copy-Item -LiteralPath $src -Destination $dest -Recurse
                Say-Green "  $verb $name"
            }
            Move-Item -LiteralPath $zip.FullName -Destination (Join-Path $installedDir $zip.Name) -Force
        }
        catch {
            $failed++
            Say-Red "  $($zip.Name): $($_.Exception.Message)"
        }
        finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
        }
    }
    Write-Host "`nDone. Type /reload in game for updates; restart the game for newly added addons."
    if ($failed) { Write-Host "$failed zip(s) failed and were left in place." -ForegroundColor Yellow }
}

# --- backups ---------------------------------------------------------------------
function Ensure-Repo {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'Backups need Git for Windows: https://git-scm.com/download/win' }
    if (-not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) {
        if (-not $script:BackupRemote) {
            $script:BackupRemote = (Read-Host 'Private GitHub repo URL for backups (e.g. https://github.com/YOU/wowaddons-backup.git)').Trim()
            if (-not $script:BackupRemote) { Fail 'No repo URL given.' }
            Set-Content -LiteralPath $RemoteFile -Value $script:BackupRemote
        }
        $ErrorActionPreference = 'Continue'
        & git clone -q $script:BackupRemote $Repo | Out-Host
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) {
            # empty new repo: start one locally pointing at the remote
            New-Item -ItemType Directory -Force -Path $Repo | Out-Null
            & git -C $Repo init -q -b main | Out-Host
            & git -C $Repo remote add origin $script:BackupRemote | Out-Host
        }
        $ErrorActionPreference = 'Stop'
    }
    if (-not (Git-Out config user.name))  { Git-Run config user.name 'wow-backup' | Out-Null }
    if (-not (Git-Out config user.email)) { Git-Run config user.email 'wow-backup@localhost' | Out-Null }
}

# Files worth keeping, as paths relative to WTF.
function Get-BackupFiles {
    $names = @('macros-cache.txt', 'bindings-cache.wtf', 'config-cache.wtf', 'AddOns.txt', 'layout-local.txt', 'chat-cache.txt')
    $list = @()
    if (Test-Path -LiteralPath (Join-Path $WTF 'Config.wtf')) { $list += 'Config.wtf' }
    $acct = Join-Path $WTF 'Account'
    if (Test-Path -LiteralPath $acct) {
        Get-ChildItem -LiteralPath $acct -Recurse -File | Where-Object {
            ($_.Directory.Name -eq 'SavedVariables' -and $_.Extension -eq '.lua') -or ($names -contains $_.Name)
        } | ForEach-Object { $list += $_.FullName.Substring($WTF.Length + 1) }
    }
    return $list
}

function Do-Backup {
    if (-not (Test-Path -LiteralPath $WTF)) { Fail "WTF folder not found at $WTF" }
    Ensure-Repo
    Git-Run pull -q --ff-only | Out-Null
    if (Test-GameRunning) { Write-Host 'Note: WoW is running. It saves addon data on logout or /reload, so the newest changes may be missing.' }

    $dest = Join-Path $Repo 'WTF'
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    $files = @(Get-BackupFiles)
    foreach ($f in $files) {
        $target = Join-Path $dest $f
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath (Join-Path $WTF $f) -Destination $target
    }
    $readme = Join-Path $Repo 'README.md'
    if (-not (Test-Path -LiteralPath $readme)) { Set-Content -LiteralPath $readme -Value "# WoW addon data backup`n`nMade by install-addons. Keep this repo private." }

    Git-Run add -A | Out-Null
    $rc = Git-Run diff --cached --quiet
    if ($rc -eq 0) { Say-Green "No changes since the last backup ($($files.Count) files)."; return }
    Git-Run commit -q -m "Backup $(Get-Date -Format 'yyyy-MM-dd HH:mm') from $env:COMPUTERNAME" | Out-Null
    if ((Git-Run push -q -u origin HEAD) -eq 0) {
        Say-Green "Backed up $($files.Count) files and pushed."
    } else {
        Say-Red "Backed up $($files.Count) files locally, but the push failed. Check the repo URL and your GitHub login, then run backup again."
    }
}

function Do-List {
    Ensure-Repo
    Git-Run fetch -q | Out-Null
    $ref = Git-Out rev-parse --abbrev-ref '@{u}'
    if (-not $ref) { $ref = 'HEAD' }
    $log = Git-Out log --format='%h  %s' -n 20 $ref
    if ($log) { Write-Host $log } else { Write-Host 'No backups yet.' }
}

function Do-Restore([string]$ref) {
    Ensure-Repo
    Git-Run pull -q --ff-only | Out-Null
    if (-not $ref) { $ref = 'HEAD' }
    if (-not (Git-Out rev-parse -q --verify "$ref^{commit}")) { Fail "Unknown backup: $ref (see: install-addons.bat list)" }
    if (Test-GameRunning) { Fail 'Close WoW first; it would overwrite the restored files when you log out.' }

    if (Test-Path -LiteralPath $WTF) {
        $safety = Join-Path $Here ("wtf-before-restore-$(Get-Date -Format 'yyyyMMdd-HHmmss').zip")
        Compress-Archive -LiteralPath $WTF -DestinationPath $safety
        Write-Host "Saved the current WTF folder to $safety"
    }
    $tmp = Join-Path $env:TEMP ('wtfrestore_' + [guid]::NewGuid())
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $tmp 'backup.zip'
    if ((Git-Run archive --format=zip -o $zip $ref WTF) -ne 0) { Fail 'Could not read that backup.' }
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Force -Path $WTF | Out-Null
    Copy-Item -Path (Join-Path $tmp 'WTF\*') -Destination $WTF -Recurse -Force
    Remove-Item -LiteralPath $tmp -Recurse -Force
    Say-Green "Restored backup $(Git-Out log -1 --format='%h (%s)' $ref)."
}

# --- main ------------------------------------------------------------------------
switch ($Command.ToLower()) {
    'backup'  { Do-Backup }
    'list'    { Do-List }
    'restore' { Do-Restore $Id }
    'pull'    { Do-Restore '' }
    ''        {
        if (-not $NoBackup) {
            if ($BackupRemote) {
                Write-Host 'Backing up addon data first...'
                try { Do-Backup } catch { Say-Red "Backup failed ($($_.Exception.Message)); installing anyway." }
                Write-Host ''
            } else {
                Write-Host "(Tip: run 'install-addons.bat backup' once to set up automatic backups of your addon data.)`n"
            }
        }
        Do-Install
    }
    default { Write-Host 'Usage: install-addons.bat [-NoBackup] | backup | list | pull | restore [id]'; exit 1 }
}
