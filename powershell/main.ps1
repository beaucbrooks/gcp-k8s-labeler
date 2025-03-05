. .\src\logging.ps1
. .\src\K8sLabelManager.ps1

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "$PSScriptRoot\gke_cluster_export_$timestamp.log"
$csvOutputPath = "$PSScriptRoot\gke_cluster_labels_$timestamp.csv"

Set-EnvironmentVariables -Path "..\.env"
Set-KubeConfigPath
Connect-GCP
Get-CombinedInformation | Export-Csv -Path "$csvOutputPath" -NoTypeInformation
Write-Summary -LogPath "$logFile" -CsvPath "$csvOutputPath"