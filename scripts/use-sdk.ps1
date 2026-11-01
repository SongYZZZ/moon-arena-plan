param([Parameter(Mandatory=$true)][string]$SdkHome)
$ArenaSdk = (Resolve-Path -LiteralPath $SdkHome -ErrorAction Stop).Path
$ArenaVersion = & (Join-Path $ArenaSdk 'bin/moon.exe') version --all
if ($LASTEXITCODE -ne 0 -or ($ArenaVersion -join "`n") -notmatch 'moonc v0\.10\.(1[6-9]|[2-9][0-9])') { throw 'moonc >= 0.10.16 is required; use matching SDK and core.' }
$env:MOON_HOME=$ArenaSdk
$env:PATH=(Join-Path $ArenaSdk 'bin')+';'+$env:PATH
$ArenaVersion
