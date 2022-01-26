$baseDir = ".\templates\"
$outputDir = ".\output"

if(Test-Path -Path $outputDir) {
    Remove-Item -Path $outputDir -Recurse
}

$releaseDirectory = New-Item -ItemType Directory -Path ".\" -Name $outputDir

$metadataInfo = @()

$templates = Get-ChildItem -Path $baseDir
foreach($template in $templates) {
    $templateMetadataFile = Join-Path $template.FullName "template.json"
    if(-not(Test-Path -Path $templateMetadataFile)) {
        Write-Output "Skipping template $($template.Name) due to missing metadata file."
        continue
    }

    $metadata = Get-Content -Path $templateMetadataFile | ConvertFrom-Json
    $metadataTable = @{}
    $metadata.psobject.Properties | ForEach-Object { $metadataTable[$_.Name] = $_.Value }

    $metadataTable["directory"] = $template.Name
    $metadataTable["package"] = "$($template.Name).zip"

    $files = Get-ChildItem -Path $template.FullName -Exclude "template.json"
    $outputFile = Join-Path -Path $releaseDirectory -ChildPath $metadataTable["package"]
    Compress-Archive -Path $files -DestinationPath $outputFile -CompressionLevel Optimal -Force

    #$templateDirectory = New-Item -ItemType Directory -Path $releaseDirectory.FullName -Name $metadataTable["directory"]
    #Copy-Item -Path $files -Destination $templateDirectory
    #Compress-Archive -Path "$($templateDirectory.FullName)" -DestinationPath $outputFile -CompressionLevel Optimal -Force
    #Remove-Item -Path $templateDirectory -Recurse

    $metadataInfo += $metadataTable
    $metadataInfo += $metadataTable
}

ConvertTo-Json $metadataInfo | Out-File -FilePath (Join-Path $releaseDirectory.FullName "templates.json")
