# setup-claude.ps1 — Claude Code configuration installer for Windows
# Run: powershell -ExecutionPolicy Bypass -File setup-claude.ps1

$ErrorActionPreference = "Stop"

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"

Write-Host ""
Write-Host "  Claude Code Configuration Installer (Windows)" -ForegroundColor Green
Write-Host ("=" * 58) -ForegroundColor Green
Write-Host ""
Write-Host "Repository: $RepoDir" -ForegroundColor Yellow
Write-Host "Target:     $ClaudeDir" -ForegroundColor Yellow
Write-Host ""

# Check Claude Code is installed
if (-not (Test-Path $ClaudeDir)) {
    Write-Host "Error: $ClaudeDir not found." -ForegroundColor Red
    Write-Host "Install Claude Code first: https://claude.ai/code"
    exit 1
}

# Backup
$BackupDir = "$ClaudeDir.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Write-Host "Creating backup at: $BackupDir" -ForegroundColor Yellow
Copy-Item -Path $ClaudeDir -Destination $BackupDir -Recurse -Force
Write-Host "  Backup created" -ForegroundColor Green
Write-Host ""

# Audio prompt
Write-Host "Install audio notifications? (plays sounds on task completion)" -ForegroundColor Cyan
Write-Host "  Requires: Python 3 installed"
Write-Host "  Audio files: ~2MB"
$audioChoice = Read-Host "Install audio? (y/N)"
$installAudio = $audioChoice -eq "y" -or $audioChoice -eq "Y"
Write-Host ""

# Helper: create symlink or copy
function Install-Item {
    param(
        [string]$Source,
        [string]$Target,
        [string]$Name,
        [switch]$IsDirectory
    )

    # Remove existing
    if (Test-Path $Target) {
        if ((Get-Item $Target).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            # It's a symlink/junction — remove it
            if ($IsDirectory) {
                cmd /c "rmdir `"$Target`"" 2>$null
            } else {
                Remove-Item $Target -Force
            }
        } elseif (Test-Path $Target) {
            # Real file/dir — back it up
            $backupPath = "$Target.old.$(Get-Date -Format 'HHmmss')"
            Move-Item $Target $backupPath
            Write-Host "    Backed up existing $Name" -ForegroundColor Yellow
        }
    }

    # Try symlink first, fall back to copy
    try {
        if ($IsDirectory) {
            cmd /c "mklink /D `"$Target`" `"$Source`"" 2>$null | Out-Null
        } else {
            cmd /c "mklink `"$Target`" `"$Source`"" 2>$null | Out-Null
        }
        if ($LASTEXITCODE -ne 0) { throw "mklink failed" }
        Write-Host "  Linked $Name" -ForegroundColor Green
    } catch {
        # Symlinks may require Developer Mode or admin — fall back to copy
        if ($IsDirectory) {
            Copy-Item -Path $Source -Destination $Target -Recurse -Force
        } else {
            Copy-Item -Path $Source -Destination $Target -Force
        }
        Write-Host "  Copied $Name (enable Developer Mode for symlinks)" -ForegroundColor Yellow
    }
}

# Install directories
Write-Host "Installing directories..." -ForegroundColor Yellow
Install-Item -Source "$RepoDir\hooks" -Target "$ClaudeDir\hooks" -Name "hooks/" -IsDirectory
Install-Item -Source "$RepoDir\commands" -Target "$ClaudeDir\commands" -Name "commands/" -IsDirectory

if (Test-Path "$RepoDir\agents") {
    Install-Item -Source "$RepoDir\agents" -Target "$ClaudeDir\agents" -Name "agents/" -IsDirectory
}

if ($installAudio) {
    Install-Item -Source "$RepoDir\audio" -Target "$ClaudeDir\audio" -Name "audio/" -IsDirectory
} else {
    # Remove audio dir if it exists (makes play_audio.py a no-op)
    if (Test-Path "$ClaudeDir\audio") {
        Remove-Item "$ClaudeDir\audio" -Recurse -Force 2>$null
    }
    Write-Host "  Skipped audio/ (notifications disabled)" -ForegroundColor DarkGray
}
Write-Host ""

# Install files
Write-Host "Installing files..." -ForegroundColor Yellow
Install-Item -Source "$RepoDir\settings.json" -Target "$ClaudeDir\settings.json" -Name "settings.json"
Install-Item -Source "$RepoDir\CLAUDE.md" -Target "$ClaudeDir\CLAUDE.md" -Name "CLAUDE.md"
Install-Item -Source "$RepoDir\statusline-command.sh" -Target "$ClaudeDir\statusline-command.sh" -Name "statusline-command.sh"

if (Test-Path "$RepoDir\claude.json") {
    Install-Item -Source "$RepoDir\claude.json" -Target "$ClaudeDir\claude.json" -Name "claude.json"
}
Write-Host ""

# Check dependencies
Write-Host "Checking dependencies..." -ForegroundColor Yellow
$deps = @("git", "python3", "node")
foreach ($dep in $deps) {
    if (Get-Command $dep -ErrorAction SilentlyContinue) {
        Write-Host "  $dep installed" -ForegroundColor Green
    } else {
        # python3 might be 'python' on Windows
        if ($dep -eq "python3" -and (Get-Command "python" -ErrorAction SilentlyContinue)) {
            Write-Host "  python installed (as 'python')" -ForegroundColor Green
        } else {
            Write-Host "  $dep not found" -ForegroundColor Red
        }
    }
}
Write-Host ""

# Star the repo
Write-Host "Star the meirpro-dotfiles repo on GitHub?" -ForegroundColor Cyan
Write-Host "  (Helps others discover these tools)"
$starChoice = Read-Host "Star repo? (y/N)"
if ($starChoice -eq "y" -or $starChoice -eq "Y") {
    if (Get-Command "gh" -ErrorAction SilentlyContinue) {
        try {
            gh api user/starred/meirpro/meirpro-dotfiles -X PUT 2>$null
            Write-Host "  Starred meirpro/meirpro-dotfiles" -ForegroundColor Green
        } catch {
            Write-Host "  Could not star — run 'gh auth login' first" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  GitHub CLI (gh) not installed — star manually:" -ForegroundColor Yellow
        Write-Host "  https://github.com/meirpro/meirpro-dotfiles" -ForegroundColor Cyan
    }
}
Write-Host ""

# Done
Write-Host ("=" * 58) -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host ("=" * 58) -ForegroundColor Green
Write-Host ""
Write-Host "Features installed:" -ForegroundColor Yellow
Write-Host "  - Auto TypeScript checking on every file edit"
Write-Host "  - Auto ESLint on every file edit"
Write-Host "  - Auto Prettier formatting on every file edit"
Write-Host "  - Security rules (blocks reading .env, secrets, keys)"
Write-Host "  - Git safety rules (no git add -A, no co-author lines)"
Write-Host "  - Status line with git info, cost tracking, session ID"
if ($installAudio) {
    Write-Host "  - Audio notifications on task completion"
}
Write-Host ""
Write-Host "Next: Restart Claude Code or start a new session." -ForegroundColor Yellow
Write-Host ""
