<powershell>
$logFile = "c:/user-data.log"
New-Item $logFile -ItemType file

write-output "Setting up variables" | Out-File $logFile -append

$tentacleDownloadPath = "http://octopusdeploy.com/downloads/latest/OctopusTentacle64"
$apiKey = "<Octopus API key>"
$octopusServerPrivateIP = "<Octopus private IP>"
$environment = "<Octopus Environment Name>"
$role = "<Octopus Role>"
$octopusServerThumbprint = "<Octopus Server Thumbprint>"
$tentacleListenPort = 10933
$tentacleHomeDirectory = "$env:SystemDrive:\Octopus"
$tentacleAppDirectory = "$env:SystemDrive:\Octopus\Applications"
$tentacleConfigFile = "$env:SystemDrive\Octopus\Tentacle\Tentacle.config"
$instanceId = Invoke-RestMethod -Method Get -Uri http://169.254.169.254/latest/meta-data/instance-id
$ipAddress = Invoke-RestMethod -Method Get -Uri http://169.254.169.254/latest/meta-data/local-ipv4
$projectName = "<Project Name>"

write-output "Downloading latest Octopus Tentacle MSI" | Out-File $logFile -append

$tentaclePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(".\Tentacle.msi")
if ((test-path $tentaclePath) -ne $true) {
  write-output "Downloading $tentacleDownloadPath to $tentaclePath" | Out-File $logFile -append
  write-output "Ignoring Security sessioning for this shell" | Out-File $logFile -append
  [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $downloader = new-object System.Net.WebClient
  $downloader.DownloadFile($tentacleDownloadPath, $tentaclePath)
}
  
write-output "Installing latest Octopus Tentacle MSI" | Out-File $logFile -append
$msiExitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/i Tentacle.msi /quiet" -Wait -Passthru).ExitCode
write-output "Tentacle MSI installer returned exit code $msiExitCode" | Out-File $logFile -append
if ($msiExitCode -ne 0) {
  throw "Installation aborted"
}
write-output "Open port $tentacleListenPort on Windows Firewall" | Out-File $logFile -append
& netsh.exe firewall add portopening TCP $tentacleListenPort "Octopus Tentacle"
if ($lastExitCode -ne 0) {
  throw "Installation failed when modifying firewall rules"
}
  
$ipAddress = $ipAddress.Trim()
write-output "Private IP address: " + $ipAddress | Out-File $logFile -append
 
write-output "Configuring and registering Tentacle" | Out-File $logFile -append
  
cd "$${env:ProgramFiles}\Octopus Deploy\Tentacle"
& .\tentacle.exe create-instance --instance "Tentacle" --config $tentacleConfigFile --console | write-output | Out-File $logFile -append
if ($lastExitCode -ne 0) {
  throw "Installation failed on create-instance"
}
& .\tentacle.exe configure --instance "Tentacle" --home $tentacleHomeDirectory --console | write-output | Out-File $logFile -append
if ($lastExitCode -ne 0) {
  throw "Installation failed on configure"
}
& .\tentacle.exe configure --instance "Tentacle" --app $tentacleAppDirectory --console | write-output | Out-File $logFile -append
if ($lastExitCode -ne 0) {
  throw "Installation failed on configure"
}
& .\tentacle.exe configure --instance "Tentacle" --port $tentacleListenPort --console | write-output | Out-File $logFile -append
if ($lastExitCode -ne 0) {
  throw "Installation failed on configure"
}
& .\tentacle.exe new-certificate --instance "Tentacle" --console | write-output | Out-File $logFile -append
if ($lastExitCode -ne 0) {
  throw "Installation failed on creating new certificate"
}
& .\tentacle.exe configure --instance "Tentacle" --trust $octopusServerThumbprint --console  | write-output | Out-File $logFile -append
if ($lastExitCode -ne 0) {
  throw "Installation failed on configure"
}
& .\tentacle.exe register-with --instance "Tentacle" --server http://$octopusServerPrivateIP --environment $environment --role $role --name $instanceId --publicHostName $ipAddress --apiKey $apiKey --comms-style TentaclePassive --force --console | write-output | Out-File $logFile -append
if ($lastExitCode -ne 0) {
  throw "Installation failed on register-with"
}
 
& .\tentacle.exe service --instance "Tentacle" --install --start --console | write-output | Out-File $logFile -append
if ($lastExitCode -ne 0) {
  throw "Installation failed on service install"
}
write-output "Tentacle installations complete" | Out-File $logFile -append

write-output "Tagging EC2 instance with Octopus Machine ID" | Out-File $logFile -append

Import-Module AWSPowerShell

Add-Type -Path "C:\Program Files\Octopus Deploy\Tentacle\Newtonsoft.Json.dll" # Path to Newtonsoft.Json.dll 
Add-Type -Path "C:\Program Files\Octopus Deploy\Tentacle\Octopus.Client.dll" # Path to Octopus.Client.dll

$endpoint = new-object Octopus.Client.OctopusServerEndpoint http://$octopusServerPrivateIP,$apiKey 
$repository = new-object Octopus.Client.OctopusRepository $endpoint 
$findmachine = $repository.Machines.FindByName("$instanceId") 
$octopusMachineid = $findmachine.id

New-EC2Tag -Resource $instanceId -Tag @{ Key="OctopusMachineId"; Value=$octopusMachineid }  -Region "${region}"
write-output "Set OctopusMachineId to $octopusMachineid" | Out-File $logFile -append

Write-Output "Deploying latest version of the application" | Out-File $logFile -append
$Header =  @{ "X-Octopus-ApiKey" = $apiKey } # This header is used in all the octopus rest api calls

Write-Output "Getting Build for project: $projectName" | Out-File $logFile -append
  
$Project = Invoke-WebRequest -UseBasicParsing  -Uri http://$octopusServerPrivateIP/api/projects/$ProjectName -Headers $Header| ConvertFrom-Json
$projectId = $Project.Id

$Environments = Invoke-WebRequest -UseBasicParsing  -Uri http://$octopusServerPrivateIP/api/Environments/all -Headers $Header| ConvertFrom-Json
$OctopusEnvironment = $Environments | ?{$_.name -eq $environment}
$environmentId = $OctopusEnvironment.Id

$LatestRelease = Invoke-WebRequest -UseBasicParsing  -Uri "http://$octopusServerPrivateIP/api/deployments?Environments=$environmentId&Projects=$projectId&SpecificMachineIds=instanceId&Take=1"  -Headers $Header  | ConvertFrom-Json
$LatestReleaseId = $LatestRelease.Items[0].ReleaseID

Write-Output "LatestReleaseId: $LatestReleaseId" | Out-File $logFile -append

[string[]] $MachineNames = $OctopusMachineId

$DeploymentBody = @{ 
			ReleaseID = $LatestReleaseId
			EnvironmentID = $environmentId
			SpecificMachineIds = $MachineNames
		  } | ConvertTo-Json

Write-Output "Deployment params: $DeploymentBody" | Out-File $logFile -append
		 
Write-Output "Deploying project $projectName to $OctopusMachineId" | Out-File $logFile -append
$deployment = Invoke-WebRequest -Uri http://$octopusServerPrivateIP/api/deployments -Method Post -Headers $Header -Body $DeploymentBody

</powershell>
<persist>true</persist>