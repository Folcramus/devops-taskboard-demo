param(
    [Parameter(Mandatory = $true)][string]$ServerIp,
    [string]$PrivateKey = "$HOME\.ssh\taskboard_deploy"
)

$ErrorActionPreference = "Stop"
$PublicKey = "$PrivateKey.pub"

foreach ($program in @("ssh", "scp")) {
    if (-not (Get-Command $program -ErrorAction SilentlyContinue)) {
        throw "OpenSSH client is required. Missing command: $program"
    }
}
if (-not (Test-Path -LiteralPath $PublicKey)) {
    throw "Public SSH key missing: $PublicKey. Generate keys first."
}

$Root = "root@$ServerIp"
Write-Host "Step 1/3. Copy public SSH key to root home. Enter root password only in the SSH prompt."
& scp -o StrictHostKeyChecking=ask $PublicKey "${Root}:/root/taskboard_deploy.pub"
if ($LASTEXITCODE -ne 0) { throw "SCP failed" }

Write-Host "Step 2/3. Install Docker and prepare the deploy user."
$Bootstrap = "curl -fsSL https://raw.githubusercontent.com/Folcramus/devops-taskboard-demo/main/scripts/bootstrap-server.sh -o /root/taskboard-bootstrap.sh && bash /root/taskboard-bootstrap.sh /root/taskboard_deploy.pub"
& ssh -o StrictHostKeyChecking=ask $Root $Bootstrap
if ($LASTEXITCODE -ne 0) { throw "Server bootstrap failed. Check server log before continuing." }

Write-Host "Step 3/3. Verify deploy access using SSH key."
& ssh -o BatchMode=yes -i $PrivateKey "deploy@$ServerIp" "cd /opt/devops-taskboard && bash scripts/server-preflight.sh"
if ($LASTEXITCODE -ne 0) { throw "Deploy login or server preflight failed" }
Write-Host "Ubuntu server prepared. Next: configure GitHub Actions Secrets." -ForegroundColor Green
