# Put your 'secret' values in a file named .env
# with the format of KEY=VALUE .NO QUOTES NO SPACES.
if(Test-Path "$PSScriptRoot/.env") {
    Get-Content "$PSScriptRoot/.env" | ForEach-Object {
        $key, $value = $_ -split '='
        Set-Item -Path "env:$key" -Value $value
    }
}
$credentialsPath = $env:GOOGLE_APPLICATION_CREDENTIALS
$projectId = Get-Content $credentialsPath | ConvertFrom-Json | Select-Object -ExpandProperty project_id
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "$PSScriptRoot\gke_cluster_export_$timestamp.log"
$csvOutputPath = "$PSScriptRoot\gke_cluster_labels_$timestamp.csv"
$missingConfigs = @()
$totalClusters = 0
$successfulExports = 0
$failedExports = 0

# Initialize CSV with headers
$csvHeaders = @(
    'PROJECT-ID',
    'CLUSTER-NAME',
    'LOCATION',
    'CLUSTER-VERSION',
    'NODE-COUNT',
    'STATUS',
    'NETWORK',
    'SUBNET',
    'CREATION-TIMESTAMP',
    'TOTAL-LABELS',
    'EXPORT-DATE'
)

# Create CSV file with headers
$csvHeaders -join ',' | Out-File -FilePath $csvOutputPath -Encoding UTF8

function Write-Log {
    param($Message, $Level = "INFO")
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')|$Level|$Message"
    Add-Content -Path $logFile -Value $logMessage
    if ($Level -eq "ERROR") {
        Write-Error $Message
    } elseif ($VerbosePreference -eq 'Continue' -or $Level -eq "INFO") {
        Write-Host $logMessage
    }
}

function Write-ToCSV {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$ClusterInfo
    )
    
    # Create array to hold row data in correct order
    $rowData = @()
    foreach ($header in $csvHeaders) {
        $rowData += if ($null -ne $ClusterInfo[$header]) { 
            "`"$($ClusterInfo[$header])`""
        } else { 
            '""'
        }
    }
    
    # Append row to CSV
    $rowData -join ',' | Add-Content -Path $csvOutputPath -Encoding UTF8
}

function Connect-GCP {
    try {
        Write-Log "Attempting GCP login with Service Account"
        gcloud auth activate-service-account --key-file=$credentialsPath
        gcloud config set project $projectId
        Write-Log "GCP login successful for project: $projectId"
    }
    catch {
        <#Do this if a terminating exception happens#>
        Write-Log "Failed to login to GCP: $_" -Level "ERROR"
        exit 1
    }
}

function Get-ClusterInfo {
    try {
        # Get GKE clusters
        Write-Log "Getting GKE clusters in project $projectId"
        $clusters = gcloud container clusters list --format="json" | ConvertFrom-Json
        
        if ($clusters) {
            Write-Log "Found $($clusters.Count) GKE clusters in project $projectId"
            
            foreach ($cluster in $clusters) {
                $totalClusters++
                $clusterName = $cluster.name
                $location = $cluster.location
                
                try {
                    Write-Log "Processing cluster: $clusterName in $location"
                    
                    # Get detailed cluster information
                    $clusterDetail = gcloud container clusters describe $clusterName --region=$location --format="json" | ConvertFrom-Json
                    
                    # Extract labels
                    $labels = @{}
                    if ($clusterDetail.resourceLabels) {
                        $labels = $clusterDetail.resourceLabels
                    }
                    
                    # Create cluster info
                    $clusterInfo = @{
                        'PROJECT-ID' = $projectId
                        'CLUSTER-NAME' = $clusterName
                        'LOCATION' = $location
                        'CLUSTER-VERSION' = $clusterDetail.currentMasterVersion
                        'NODE-COUNT' = $clusterDetail.currentNodeCount
                        'STATUS' = $clusterDetail.status
                        'NETWORK' = $clusterDetail.network
                        'SUBNET' = $clusterDetail.subnetwork
                        'CREATION-TIMESTAMP' = $clusterDetail.createTime
                        'TOTAL-LABELS' = $labels.Count
                        'EXPORT-DATE' = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    }
                    
                    # Write to CSV
                    Write-ToCSV -ClusterInfo $clusterInfo
                    
                    $successfulExports++
                    Write-Log "Successfully analyzed cluster: $clusterName"
                    
                } catch {
                    Write-Log "Failed to analyze cluster $clusterName. Error: $_" -Level "ERROR"
                    $missingConfigs += "$projectId : $clusterName"
                    $failedExports++
                }
            }
        } else {
            Write-Log "No GKE clusters found in project $projectId" -Level "INFO"
        }
    } catch {
        Write-Log "Failed to process project $projectId. Error: $_" -Level "ERROR"
        $failedExports++
    }
}

function Write-Summary {
    Write-Log "`n=== EXPORT SUMMARY ===" -Level "WARNING"
    Write-Log "Total clusters processed: $totalClusters"
    Write-Log "Successful exports: $successfulExports"
    Write-Log "Failed exports: $failedExports"

    if ($missingConfigs.Count -gt 0) {
        Write-Log "`n=== FAILED EXPORTS ===" -Level "ERROR"
        foreach ($missing in $missingConfigs) {
            Write-Log "  - $missing" -Level "ERROR"
        }
    }

    Write-Log "`nCluster analysis complete"
    Write-Log "Results exported to: $csvOutputPath"
    Write-Log "Full execution log available at: $logFile"
}

Connect-GCP
Get-ClusterInfo
Write-Summary