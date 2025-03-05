$global:MISING_CONFIGS = @()
$global:PROJECT_ID = Get-Content $env:GOOGLE_APPLICATION_CREDENTIALS | ConvertFrom-Json | Select-Object -ExpandProperty project_id
$global:TOTAL_CLUSTERS = 0
$global:SUCCESSFUL_EXPORTS = 0
$global:FAILED_EXPORTS = 0

# Put your 'secret' values in a file named .env
# with the format of KEY=VALUE .NO QUOTES NO SPACES.
function Set-EnvironmentVariables {
    param(
        [string]$Path = "$PSScriptRoot/.env"   
    )

    if (Test-Path "$Path") {
        Get-Content "$Path" | ForEach-Object {
            $key, $value = $_ -split '='
            Set-Item -Path "env:$key" -Value $value
        }
    }
    else {
        Write-Log "No .env file found, not sure where you're getting your secrets/credentials from. Exiting..." -Level "ERROR"
        exit 1
    }
}

function Set-KubeConfigPath {
    param(
        [string]$Path = "$env:USERPROFILE\.kube"
    )

    if (Test-Path "$env:USERPROFILE\.kube") {
        $env:Path += ";$env:USERPROFILE\.kube"
    }
    else {
        Write-Log "Kube config not found, without it you will not be able to pull label info. Exiting..." -Level "ERROR"
        exit 1
    }
}

function Connect-GCP {
    param(
        [string]$KeyPath = $env:GOOGLE_APPLICATION_CREDENTIALS
    )
    try {
        Write-Log "Attempting GCP login with Service Account" 
        gcloud auth activate-service-account --key-file=$env:GOOGLE_APPLICATION_CREDENTIALS
        gcloud config set project $global:PROJECT_ID
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

function Get-GKEClusters {
    param(
        [string]$projectId
    )
    $clusters = $null
    Write-Log "Getting GKE clusters in project $projectId"
    try {
        $clusters = gcloud container clusters list --format="json" | ConvertFrom-Json
    }
    catch {
        Write-Log "Failed to get GKE clusters: $_" -Level "ERROR"
    }
    return $clusters
}

function Get-ClusterInfo {
    $clusterInfoResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    $clusters = Get-GKEClusters -projectId $global:PROJECT_ID 
    try {
        if ($clusters) {
            foreach ($cluster in $clusters) {
                $global:TOTAL_CLUSTERS++
                $clusterName = $cluster.name
                $location = $cluster.location
                try {
                    Write-Log "Processing cluster: $clusterName in $location"
                    $clusterDetail = gcloud container clusters describe $clusterName --region=$location --format="json" | ConvertFrom-Json
                    $clusterInfo = [PSCustomObject]@{
                        project    = $global:PROJECT_ID
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
                    $global:MISSING_CONFIGS += "$global:PROJECT_ID : $clusterName"
                    $global:FAILED_EXPORTS++
                }
            }
        }
        else {
            Write-Log "No clusters found in project $global:PROJECT_ID" -Level "INFO"
        }
    }
    catch {
        Write-Log "Failed to process project $global:PROJECT_ID. Error: $_" -Level "ERROR"
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
    param(
        [string]$CsvOutputPath,
        [string]$LogPath
    )
    Write-Log "`n=== EXPORT SUMMARY ===" 
    Write-Log "Total clusters processed: $global:TOTAL_CLUSTERS"
    Write-Log "Successful exports: $global:SUCCESSFUL_EXPORTS"
    Write-Log "Failed exports: $global:FAILED_EXPORTS"

    if ($global:MISING_CONFIGS.Count -gt 0) {
        Write-Log "`n=== FAILED EXPORTS ===" -Level "ERROR"
        foreach ($missing in $global:MISING_CONFIGS) {
            Write-Log "  - $missing" -Level "ERROR"
        }
    }

    Write-Log "`nCluster analysis complete"
    Write-Log "Results exported to: $CsvOutputPath"
    Write-Log "Full execution log available at: $LogPath"
}
