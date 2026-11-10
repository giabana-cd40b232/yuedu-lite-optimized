# 发布脚本：复制IPA到Downloads并同步发布到GitHub和Gitee
param(
    [string]$IpaPath = "",
    [string]$Version = "",
    [string]$Build = "",
    [switch]$SkipCopy = $false,
    [switch]$SkipPublish = $false
)

$ErrorActionPreference = "Stop"

# 获取下载文件夹
$DownloadsPath = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
if (-not (Test-Path $DownloadsPath)) {
    New-Item -ItemType Directory -Path $DownloadsPath -Force | Out-Null
}

# 从Info.plist读取版本信息
if (-not $Version -or -not $Build) {
    $infoPlist = ".\Resources\Info.plist"
    if (Test-Path $infoPlist) {
        try {
            [xml]$plist = Get-Content $infoPlist -Raw
            $dict = $plist.plist.dict
            $keys = $dict.key
            $strings = $dict.string
            for ($i = 0; $i < $keys.Count; $i++) {
                if ($keys[$i] -eq "CFBundleShortVersionString" -and -not $Version) {
                    $Version = $strings[$i]
                }
                if ($keys[$i] -eq "CFBundleVersion" -and -not $Build) {
                    $Build = $strings[$i]
                }
            }
        } catch {
            Write-Host "无法读取Info.plist版本信息" -ForegroundColor Yellow
        }
    }
}

if (-not $Version) { $Version = "1.5" }
if (-not $Build) { $Build = "30" }

# 查找IPA文件
if (-not $IpaPath) {
    # 尝试常用位置
    $possiblePaths = @(
        ".\YueduLite.ipa",
        ".\.theos\obj\YueduLite.ipa",
        ".\packages\*.ipa",
        "..\*.ipa"
    )
    foreach ($pattern in $possiblePaths) {
        $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($found) {
            $IpaPath = $found.FullName
            break
        }
    }
}

if (-not $IpaPath -or -not (Test-Path $IpaPath)) {
    Write-Error "找不到IPA文件，请指定 -IpaPath"
    exit 1
}

Write-Host "找到IPA: $IpaPath" -ForegroundColor Green
Write-Host "版本: v$Version (build $Build)" -ForegroundColor Green

# 复制到Downloads文件夹
if (-not $SkipCopy) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $fileName = "YueduLite-v$Version-build$Build-$timestamp.ipa"
    $destPath = Join-Path $DownloadsPath $fileName
    Copy-Item -Path $IpaPath -Destination $destPath -Force
    Write-Host "已复制到Downloads: $destPath" -ForegroundColor Green
    # 同时复制一份不带时间戳的副本
    $destPath2 = Join-Path $DownloadsPath "YueduLite-v$Version-build$Build.ipa"
    Copy-Item -Path $IpaPath -Destination $destPath2 -Force
    Write-Host "已复制到Downloads: $destPath2" -ForegroundColor Green
}

# 发布到GitHub和Gitee
if (-not $SkipPublish) {
    Write-Host "开始发布到GitHub和Gitee..." -ForegroundColor Cyan
    
    # 检查GitHub CLI
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        Write-Host "检测到 GitHub CLI (gh)" -ForegroundColor Green
        try {
            $repo = "Daniel123999/yuedu-lite"
            $tag = "v$Version"
            Write-Host "发布到 GitHub: $repo tag $tag" -ForegroundColor Cyan
            # 尝试上传资产（如果release已存在）
            gh release upload $tag $IpaPath --repo $repo --clobber 2>&1
            Write-Host "GitHub发布完成" -ForegroundColor Green
        } catch {
            Write-Host "GitHub发布失败: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "未找到 gh CLI，跳过GitHub自动发布" -ForegroundColor Yellow
    }
    
    # Gitee发布
    $giteeTokenFile = "..\..\gitee_token.txt"
    $giteePublishScript = "..\..\gitee_publish.ps1"
    if (Test-Path $giteePublishScript) {
        Write-Host "检测到Gitee发布脚本，准备发布到Gitee..." -ForegroundColor Cyan
        try {
            & $giteePublishScript 2>&1
            Write-Host "Gitee发布完成" -ForegroundColor Green
        } catch {
            Write-Host "Gitee发布失败: $_" -ForegroundColor Red
        }
    } elseif (Test-Path $giteeTokenFile) {
        Write-Host "检测到Gitee token，跳过自动发布（需手动配置脚本）" -ForegroundColor Yellow
    } else {
        Write-Host "未找到Gitee配置，跳过Gitee发布" -ForegroundColor Yellow
    }
}

Write-Host "`n发布流程全部完成！" -ForegroundColor Green
Write-Host "IPA已保存到本地Downloads文件夹" -ForegroundColor Green

