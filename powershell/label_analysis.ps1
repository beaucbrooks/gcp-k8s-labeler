# Put your 'secret' values in a file named .env
# with the format of KEY=VALUE .NO QUOTES NO SPACES.
if (Test-Path "$PSScriptRoot/.env") {
    Get-Content "$PSScriptRoot/.env" | ForEach-Object {
        $key, $value = $_ -split '='
        Set-Item -Path "env:$key" -Value $value
    }
}
. "$PSScriptRoot/logging.ps1"
$env:Path += ";$env:USERPROFILE\.kube" # expecting kubectl to either be here, or in your path
$credentialsPath = $env:GOOGLE_APPLICATION_CREDENTIALS
$projectId = Get-Content $credentialsPath | ConvertFrom-Json | Select-Object -ExpandProperty project_id
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "$PSScriptRoot\gke_cluster_export_$timestamp.log"
$csvOutputPath = "$PSScriptRoot\gke_cluster_labels_$timestamp.csv"
$missingConfigs = @()
$global:TOTAL_CLUSTERS = 0
$global:SUCCESSFUL_EXPORTS = 0
$global:FAILED_EXPORTS = 0

function Connect-GCP {
    try {
        Write-Log "Attempting GCP login with Service Account" 
        gcloud auth activate-service-account --key-file=$credentialsPath
        gcloud config set project $projectId
        Write-Log "GCP login successful for project: $projectId" 
    }
    catch {
        Write-Log "Failed to login to GCP: $_" -Level "ERROR"
        exit 1
    }
}

function Get-ClusterContexts {
    Write-Log "Getting all cluster contexts"
    try {
        return kubectl config get-contexts --output=name     
    }
    catch {
        Write-Log "Failed to get cluster contexts: $_" -Level "ERROR"
        exit 1
    }    
}

function Get-NamespacesWithLabels {
    param (
        [string]$context
    )

    Write-Log "Switching context to $context"
    try {
        kubectl config use-context $context | Out-Null     
    }
    catch {
        Write-Log "Failed to switch context: $_" -Level "ERROR"
        return 
    }
    
    Write-Log "Getting all namespaces in context: $context"
    try {
        $namespaces = kubectl get namespaces -o json | ConvertFrom-Json 
    }
    catch {
        Write-Log "Failed to get namespaces: $_" -Level "ERROR"
        return 
    }
    
    $namespaceList = @()
    foreach ($ns in $namespaces.items) {
        $namespaceList += [PSCustomObject]@{
            context   = $context
            cluster   = $context -split '_' | Select-Object -Last 1
            namespace = $ns.metadata.name
            labels    = $ns.metadata.labels
        }
    }
    return $namespaceList
}

function Get-AllNamespacesWithLabels {
    $contexts = Get-ClusterContexts
    $allNamespaces = @()

    foreach ($context in $contexts) {
        Write-Log "Getting all namespaces with labels in context: $context"
        $allNamespaces += Get-NamespacesWithLabels -context $context
    }

    return $allNamespaces
}

function Set-NamespaceLabel {
    param (
        [string]$context,
        [string]$namespace,
        [string]$labelKey,
        [string]$labelValue
    )

    Write-Host "Adding label '$labelKey=$labelValue' to namespace '$namespace' in cluster '$context'..."

    kubectl config use-context $context | Out-Null

    $command = "kubectl label namespace $namespace $labelKey=$labelValue --overwrite"
    Invoke-Expression $command

    Write-Host "Label applied successfully!"
}

function Set-LabelForAllNamespaces {
    param (
        [string]$labelKey,
        [string]$labelValue
    )

    $contexts = Get-ClusterContexts

    foreach ($context in $contexts) {
        Write-Host "Processing cluster: $context"
        
        kubectl config use-context $context | Out-Null

        $namespaces = kubectl get namespaces -o json | ConvertFrom-Json
        foreach ($ns in $namespaces.items) {
            $namespaceName = $ns.metadata.name
            Write-Host "Labeling namespace: $namespaceName in cluster: $context"

            Set-NamespaceLabel -context $context -namespace $namespaceName -labelKey $labelKey -labelValue $labelValue
        }
    }
}

function Get-ClusterInfo {
    $clusterInfoResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    try {
        # Get GKE clusters
        Write-Log "Getting GKE clusters in project $projectId"
        $clusters = gcloud container clusters list --format="json" | ConvertFrom-Json
        if ($clusters) {
            Write-Log "Found $($clusters.Count) GKE clusters in project $projectId"
            foreach ($cluster in $clusters) {
                $global:TOTAL_CLUSTERS++
                $clusterName = $cluster.name
                $location = $cluster.location
                try {
                    Write-Log "Processing cluster: $clusterName in $location"
                    $clusterDetail = gcloud container clusters describe $clusterName --region=$location --format="json" | ConvertFrom-Json
                    $clusterInfo = [PSCustomObject]@{
                        project    = $projectId
                        name       = $clusterName
                        location   = $location
                        version    = $clusterDetail.currentMasterVersion
                        nodeCount  = $clusterDetail.currentNodeCount
                        status     = $clusterDetail.status
                        network    = $clusterDetail.network
                        subnet     = $clusterDetail.subnetwork
                        createdOn  = $clusterDetail.createTime
                        exportedOn = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    }
                    $global:SUCCESSFUL_EXPORTS++
                    Write-Log "Successfully analyzed cluster: $clusterName"
                    $clusterInfoResults.Add($clusterInfo)
                }
                catch {
                    Write-Log "Failed to analyze cluster $clusterName. Error: $_" -Level "ERROR"
                    $missingConfigs += "$projectId : $clusterName"
                    $global:FAILED_EXPORTS++
                }
            }
        }
        else {
            Write-Log "No clusters found in project $projectId" -Level "INFO"
        }
    }
    catch {
        Write-Log "Failed to process project $projectId. Error: $_" -Level "ERROR"
        $global:FAILED_EXPORTS++
    }
    return $clusterInfoResults
}

function Get-CombinedInformation {
    $combinedInformation = [System.Collections.Generic.List[PSCustomObject]]::new()
    $clusters = Get-ClusterInfo
    $labelInformation = Get-AllNamespacesWithLabels

    foreach ($namespace in $labelInformation) {
        $cluster = $clusters | Where-Object { $namespace.cluster -eq $_.name } | Select-Object -First 1
        $finalObject = [PSCustomObject]@{
            name       = $namespace.namespace
            cluster    = $namespace.cluster
            labels     = $namespace.labels 
            context    = $namespace.context
            project    = $cluster.project 
            location   = $cluster.location
            version    = $cluster.version
            nodeCount  = $cluster.nodeCount
            status     = $cluster.status
            network    = $cluster.network
            subnet     = $cluster.subnet
            createdOn  = $cluster.createdOn
            exportedOn = $cluster.exportedOn
        }
        $combinedInformation.Add($finalObject)
    }

    return $combinedInformation
}

function Write-Summary {
    Write-Log "`n=== EXPORT SUMMARY ===" 
    Write-Log "Total clusters processed: $global:TOTAL_CLUSTERS"
    Write-Log "Successful exports: $global:SUCCESSFUL_EXPORTS"
    Write-Log "Failed exports: $global:FAILED_EXPORTS"

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
Get-CombinedInformation | Export-Csv -Path $csvOutputPath -NoTypeInformation 
Write-Summary