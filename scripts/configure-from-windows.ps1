param(
    [Parameter(Mandatory = $true)][string]$ServerIp,
    [string]$Repository = "Folcramus/devops-taskboard-demo",
    [string]$KeyFile = "$HOME\.ssh\taskboard_deploy",
    [string]$KnownHostsFile = "$HOME\.ssh\taskboard_known_hosts"
)

$ErrorActionPreference = "Stop"
foreach ($program in @("gh", "ssh")) {
    if (-not (Get-Command $program -ErrorAction SilentlyContinue)) {
        throw "Required command '$program' was not found."
    }
}

if (-not (Test-Path -LiteralPath $KeyFile)) {
    throw "Private key does not exist: $KeyFile. Generate it with ssh-keygen -t ed25519 -f `"$KeyFile`" -N '\"\"' and install the matching public key on the server."
}
if (-not (Test-Path -LiteralPath $KnownHostsFile)) {
    throw "Verified known_hosts file missing: $KnownHostsFile. Fetch host key with ssh-keyscan, independently verify fingerprint, and save it first."
}
if ((Get-Item -LiteralPath $KnownHostsFile).Length -eq 0) {
    throw "known_hosts file is empty."
}
& gh auth status
if ($LASTEXITCODE -ne 0) { throw "Run gh auth login first." }
& gh repo view $Repository | Out-Null
if ($LASTEXITCODE -ne 0) { throw "No access to repository: $Repository" }
& ssh -i $KeyFile -o BatchMode=yes "deploy@$ServerIp" "cd /opt/devops-taskboard && bash scripts/server-preflight.sh"
if ($LASTEXITCODE -ne 0) { throw "Server preflight failed. CD has NOT been enabled." }

& gh secret set DEPLOY_HOST --body $ServerIp -R $Repository
if ($LASTEXITCODE -ne 0) { throw "Failed to write DEPLOY_HOST" }
& gh secret set DEPLOY_USER --body "deploy" -R $Repository
if ($LASTEXITCODE -ne 0) { throw "Failed to write DEPLOY_USER" }
Get-Content -LiteralPath $KeyFile -Raw | & gh secret set DEPLOY_SSH_KEY -R $Repository
if ($LASTEXITCODE -ne 0) { throw "Failed to write DEPLOY_SSH_KEY" }
Get-Content -LiteralPath $KnownHostsFile -Raw | & gh secret set DEPLOY_KNOWN_HOSTS -R $Repository
if ($LASTEXITCODE -ne 0) { throw "Failed to write DEPLOY_KNOWN_HOSTS" }

Write-Host "GitHub secrets saved. Deployment remains OFF." -ForegroundColor Green
Write-Host "Verify GHCR image is pullable by the deploy user, and only then run:"
Write-Host "gh variable set DEPLOY_ENABLED --body true -R $Repository"
Write-Host "gh workflow run ci-cd.yml -R $Repository"
