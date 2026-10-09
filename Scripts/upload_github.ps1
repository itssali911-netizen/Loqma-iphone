# Run from the unzipped project on Windows after installing Git and GitHub CLI.
# This script creates a PRIVATE repository and uploads source only. It does not
# enable spending, add Apple secrets, or publish to TestFlight/App Store.
param(
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$RepositoryName = 'luqma-iphone'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Install Git for Windows first: https://git-scm.com/download/win'
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'Install GitHub CLI first: https://cli.github.com/'
}
function Run-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed. Check the message above before retrying." }
}
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Run-Checked 'gh' @('auth', 'login', '--web', '--git-protocol', 'https', '--scopes', 'workflow')
} else {
    Run-Checked 'gh' @('auth', 'refresh', '--scopes', 'workflow')
}
Run-Checked 'gh' @('auth', 'setup-git')
if (Test-Path '.git') {
    throw 'A Git repository already exists here. Use that repository instead of creating another one.'
}
& gh repo view $RepositoryName --json name *> $null
if ($LASTEXITCODE -eq 0) {
    throw 'That repository name already exists. Run again with -RepositoryName and a new name.'
}
Run-Checked 'git' @('init', '--initial-branch=main')
Run-Checked 'git' @('add', '.')
# Use a neutral commit author; no account email is inserted into source or URLs.
Run-Checked 'git' @('-c', 'user.name=Luqma', '-c', 'user.email=source@luqma.invalid', 'commit', '-m', 'Native Luqma iPhone app with cloud build')
Run-Checked 'gh' @('repo', 'create', $RepositoryName, '--private', '--source=.', '--remote=origin', '--push')
Write-Host 'Private repository uploaded. The source push triggers the AltStore sideload build in GitHub Actions.'
Run-Checked 'gh' @('repo', 'view', '--web')
