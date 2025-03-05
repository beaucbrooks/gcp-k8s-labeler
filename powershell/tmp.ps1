$data = Import-Csv ".\data_copy.csv"
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

$allTags = @()

foreach ($row in $data) {
    $tmpTags = ConvertFrom-Json $row.tags
    foreach ($t in $tmpTags.PSObject.Properties) {
        if ($allTags -notcontains $t.Name) {
            $allTags += $t.Name
        }
    }
}

foreach ($row in $data) {
    $tmp = [PSCustomObject]@{
        container_type  = $row.containerType
        subscription_id = $row.subscriptionID
        container_name  = $row.containername
    }

    $tags = ConvertFrom-Json $row.tags
    # loop through all possible columns and see if this rows 'tags' has a value
    # for each column. If it does, add it to the row, otherwise add an empty string
    foreach ($tag in $allTags) {
        $value = if ($tags.PSObject.Properties[$tag]) { 
            # a lot of the tags are comma separated lists, so we replace the commas with pipes
            # this prevents issues inc csv files
            $tags.PSObject.Properties[$tag].Value -replace ", ", "|" 
        }
        else { 
            "" 
        }
        $tmp | Add-Member -MemberType NoteProperty -Name $tag -Value $value
    }

    $results.Add($tmp)
}

$results | Export-Csv -Path ".\output.csv" -NoTypeInformation