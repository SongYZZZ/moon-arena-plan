param([Parameter(Mandatory=$true)][string]$SdkHome)
$ArenaSdk = (Resolve-Path -LiteralPath $SdkHome -ErrorAction Stop).Path
$ArenaVersion = & (Join-Path $ArenaSdk 'bin/moon.exe') version --all
if ($LASTEXITCODE -ne 0) { throw 'Cannot read SDK version' }
$ArenaVersionText=$ArenaVersion -join "`n"
if ($ArenaVersionText -notmatch 'moonc v([0-9]+\.[0-9]+\.[0-9]+)' -or [version]$Matches[1] -lt [version]'0.10.16') { throw 'moonc >= 0.10.16 is required; use matching SDK and core.' }

$env:MOON_HOME=$ArenaSdk
$env:PATH=(Join-Path $ArenaSdk 'bin')+';'+$env:PATH
$ArenaVersion
