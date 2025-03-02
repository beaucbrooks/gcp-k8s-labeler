$clusters = gcloud container clusters list --format="json" | ConvertFrom-Json
$projectId = (gcloud config get-value project) -replace "\r", ''

foreach ($cluster in $clusters) {
    $clusterName = $cluster.name
    $zone = $cluster.location
    Write-Host "Updating kubeconfig for cluster: $clusterName in $zone"
    gcloud container clusters get-credentials $clusterName --zone $zone --project $projectId
}