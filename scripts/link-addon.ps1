<#
.SYNOPSIS
  Points the game's AddOns folder at an addon in this repo (a directory
  junction), so edits here show up in game after /reload.

.EXAMPLE
  ./scripts/link-addon.ps1 TwoColumnStats

.EXAMPLE
  # Replace an existing copy of the addon (it's moved to a backup first).
  ./scripts/link-addon.ps1 TwoColumnStats -Force
#>
param(
	[Parameter(Mandatory)] [string] $Addon,
	[string] $AddOnsPath = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns',
	[switch] $Force
)
$ErrorActionPreference = 'Stop'

$source = Join-Path (Split-Path -Parent $PSScriptRoot) "addons\$Addon"
if (-not (Test-Path (Join-Path $source "$Addon.toc"))) { throw "No addon at $source" }
if (-not (Test-Path $AddOnsPath)) { throw "AddOns folder not found: $AddOnsPath" }

$target = Join-Path $AddOnsPath $Addon
if (Test-Path $target) {
	$item = Get-Item $target -Force
	if ($item.LinkType -eq 'Junction' -and $item.Target -contains $source) {
		Write-Host "$target already points at $source"
		exit 0
	}
	if (-not $Force) { throw "$target already exists. Use -Force to move it to a backup and link instead." }
	$backup = Join-Path $env:TEMP ("$Addon-backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
	if ($item.LinkType) {
		$item.Delete()   # removes the link only, not what it points at
	} else {
		Move-Item $target $backup
		Write-Host "Moved the existing copy to $backup"
	}
}

New-Item -ItemType Junction -Path $target -Target $source | Out-Null
Write-Host "Linked $target -> $source"
