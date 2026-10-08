[CmdletBinding()]
param(
    [string] $GodotPath = 'C:\Users\Admin\Downloads\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe',
    [string] $Suite = 'foundation',
    [string[]] $Scenes,
    [ValidateRange(1, 3600)]
    [int] $TimeoutSeconds = 60,
    [string] $LogDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable does not exist: $GodotPath"
}
$resolvedGodot = (Resolve-Path -LiteralPath $GodotPath).Path

$configPath = Join-Path $PSScriptRoot 'smoke_suites.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Smoke-suite configuration is missing: $configPath"
}
$suiteConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable
if (-not $suiteConfig.ContainsKey('suites')) {
    throw 'Smoke-suite configuration has no suites object.'
}

if ($null -ne $Scenes -and $Scenes.Count -gt 0) {
    $cases = foreach ($scene in $Scenes) {
        if ($scene -notmatch '^[A-Za-z0-9_-]+\.tscn$') {
            throw "Use a scene filename such as InventoryFoundationSmoke.tscn: $scene"
        }
        @{ scene = $scene; success_marker = '' }
    }
}
else {
    if (-not $suiteConfig.suites.ContainsKey($Suite)) {
        throw "Unknown smoke suite '$Suite'. Available: $($suiteConfig.suites.Keys -join ', ')"
    }
    $cases = $suiteConfig.suites[$Suite]
}
$cases = @($cases)

if (-not $LogDirectory) {
    $LogDirectory = Join-Path ([IO.Path]::GetTempPath()) ("go-vw-smoke-" + [guid]::NewGuid().ToString('N'))
}
$null = New-Item -ItemType Directory -Path $LogDirectory -Force
$LogDirectory = (Resolve-Path -LiteralPath $LogDirectory).Path

$failed = 0
foreach ($case in $cases) {
    $scene = [string] $case.scene
    if ($scene -notmatch '^[A-Za-z0-9_-]+\.tscn$') {
        throw "Invalid scene filename in smoke-suite configuration: $scene"
    }
    $scenePath = Join-Path $projectRoot (Join-Path 'tests' $scene)
    if (-not (Test-Path -LiteralPath $scenePath -PathType Leaf)) {
        throw "Smoke scene does not exist: $scenePath"
    }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $resolvedGodot
    $startInfo.WorkingDirectory = $projectRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('--headless', '--path', $projectRoot, "res://tests/$scene")) {
        $startInfo.ArgumentList.Add([string] $argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stdoutTask = $null
    $stderrTask = $null
    $timedOut = $false
    $exitCode = -1
    $combinedOutput = ''
    $safeScene = [IO.Path]::GetFileNameWithoutExtension($scene)
    $stdoutPath = Join-Path $LogDirectory "$safeScene.stdout.log"
    $stderrPath = Join-Path $LogDirectory "$safeScene.stderr.log"

    try {
        if (-not $process.Start()) {
            throw "Could not start Godot for $scene"
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            $process.Kill($true)
        }
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($stdoutPath, $stdout)
        [IO.File]::WriteAllText($stderrPath, $stderr)
        $combinedOutput = "$stdout`n$stderr"
    }
    finally {
        $process.Dispose()
    }

    $errors = [System.Collections.Generic.List[string]]::new()
    if ($timedOut) {
        $errors.Add("timed out after $TimeoutSeconds seconds")
    }
    elseif ($exitCode -ne 0) {
        $errors.Add("exited with code $exitCode")
    }
    if ($combinedOutput -match '(?im)^SCRIPT ERROR:|^Parse Error:|^ERROR:') {
        $errors.Add('Godot reported a script, parse, or runtime error')
    }
    $expected = [string] $case.success_marker
    if (-not [string]::IsNullOrWhiteSpace($expected) -and $combinedOutput -notlike "*$expected*") {
        $errors.Add("expected completion marker was not found: $expected")
    }

    if ($errors.Count -gt 0) {
        $failed++
        Write-Host "FAIL $scene — $($errors -join '; ')"
        $tail = @($combinedOutput -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 14)
        foreach ($line in $tail) {
            Write-Host "  $line"
        }
        Write-Host "  Logs: $stdoutPath ; $stderrPath"
    }
    else {
        Write-Host "PASS $scene (exit $exitCode; marker: $expected)"
    }
}

if ($failed -gt 0) {
    Write-Host "$failed of $($cases.Count) smoke scenes failed. Logs: $LogDirectory"
    exit 1
}
Write-Host "All $($cases.Count) smoke scenes passed. Logs: $LogDirectory"
