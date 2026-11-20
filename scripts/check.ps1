<#
.SYNOPSIS
  Lints and tests every addon in Docker, the same way CI does.
.EXAMPLE
  ./scripts/check.ps1
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$image = 'wow-addons-check'

docker build --quiet --tag $image (Join-Path $repo 'tools/docker') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'docker build failed' }

docker run --rm --volume "${repo}:/repo" $image sh scripts/check.sh
exit $LASTEXITCODE
