#Gets the hashes of new Roblox versions

#$VerbosePreference = "Continue"

$CurrentDate = $(Get-Date).ToString('yyyyMMdd_HHmmss')
$ProductName = "Roblox"
$BasePath = "c:\GetHashes"
$ProductVersionsPath = "$BasePath\ProductVersions$ProductName.json"
 
$cutoffdate = Get-date "6/26/2024"
 
#example: "WindowsPlayer" = "0.661.0.6610708"
$ProductVersions = @{}
 
$HashesFound = @{}
 
$BaseURL = "http://setup.rbxcdn.com/version-"
$ManifestURL = "http://setup.rbxcdn.com/DeployHistory.txt"
 
# https://setup.rbxcdn.com/version-302fe31805ab4542-rbxPkgManifest.txt
# https://setup.rbxcdn.com/channel/zfeaturewin64_client_deploy_test/version-af6a93b0f15544f9-rbxPkgManifest.txt
 
 
function Get-7zSfxHashes {
    [CmdletBinding()]
    param(
        # The URL of the 7z SFX file to download.
        [Parameter(Mandatory = $true)]
        [string]$Url
    )
 
    # Array to hold all discovered SHA256 hashes.
    $hashes = @()
 
    # Create temporary directories for download and extraction.
    $tempBase   = [System.IO.Path]::GetTempPath()
    $downloadDir = Join-Path $tempBase ([System.Guid]::NewGuid().ToString())
    $extractDir  = Join-Path $tempBase ([System.Guid]::NewGuid().ToString())

    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
 
    try {
        # Define the full path for the downloaded file.
        $downloadedFile = Join-Path $downloadDir "download.7z"
 
        ## download a 7z sfx file
        Write-Verbose "Downloading file from $Url to $downloadedFile..."
        Invoke-WebRequest -Uri $Url -OutFile $downloadedFile
                               
        ## get SHA256 of the file if it an EXE
                                if ($URL.EndsWith(".exe")){
                                                Write-Verbose "Calculating SHA256 hash for the downloaded file..."
                                                $downloadHash = (Get-FileHash -Algorithm SHA256 -Path $downloadedFile).Hash
                                                $hashes += $downloadHash
                                } else {
                                                Write-Verbose "Skipping Calculating SHA256 hash for the downloaded file since not an EXE..."
                                }
                               
        ## decompress the file
        Write-Verbose "Extracting the 7z file to $extractDir..."
        # Build an array of arguments to avoid quoting issues.
        $arguments = @('x', $downloadedFile, "-o$extractDir", '-y')
        & 7z.exe @arguments > $null 2>&1
        if ($LASTEXITCODE -ne 0) {
            Throw "Extraction failed with exit code $LASTEXITCODE."
        }
 
        ## search the decompressed directory recursively for all exe files and get the SHA256 value of each
        Write-Verbose "Searching for EXE files in $extractDir..."
        $exeFiles = Get-ChildItem -Path $extractDir -Recurse -Include *.exe -File
        foreach ($exe in $exeFiles) {
            Write-verbose "Calculating SHA256 for $($exe.FullName)..."
            $exeHash = (Get-FileHash -Algorithm SHA256 -Path $exe.FullName).Hash
            $hashes += $exeHash
        }
    }
    finally {
        ## clean up all downloaded and decompressed files
        Write-Verbose "Cleaning up temporary files..."
        Remove-Item -Path $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
 
    ## return an array of all SHA256 hashes discovered
    return $hashes
}

function Save-KeyValuePairs {
    [CmdletBinding()]
    param (
        # The key/value pairs to save as a hashtable.
        [Parameter(Mandatory = $true)]
        [hashtable]$Pairs,
 
        # The file path where the JSON will be saved.
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
 
    try {
        # Convert the hashtable to JSON. Adjust -Depth as needed.
        $json = $Pairs | ConvertTo-Json -Depth 10
 
        # Save the JSON string to the file.
        $json | Set-Content -Path $FilePath -Encoding UTF8
    }
    catch {
        Write-Error "Error saving key/value pairs: $_"
    }
}
function Read-KeyValuePairs {
    [CmdletBinding()]
    param (
        # The file path to read the JSON from.
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
 
    if (-not (Test-Path $FilePath)) {
        Throw "File not found: '$FilePath'."
    }
 
    try {
        # Read the JSON file as a single string.
        $json = Get-Content -Path $FilePath -Raw
 
        # Convert JSON string back to a PSCustomObject.
        $object = $json | ConvertFrom-Json
 
        # Convert the PSCustomObject to a hashtable.
        $hashtable = @{}
        foreach ($property in $object.PSObject.Properties) {
            $hashtable[$property.Name] = $property.Value
        }
        return $hashtable
    }
    catch {
        Write-Error "Error reading key/value pairs: $_"
    }
}
function Parse-RobloxManifest {
    param(
        [Parameter(Mandatory)]
        [string]$LogText
    )
 
    $LogLines = $LogText -split "`r?`n"
 
    $result = foreach ($line in $LogLines) {
        if ($line -match 'New\s+(\w+)\s+version-([a-f0-9]+)\s+at\s+([\d/\s:APM]+).*?file version: (\d+, \d+, \d+, \d+)') {
            [PSCustomObject]@{
                ProductName = $matches[1]
                VersionHash = $matches[2]
                Timestamp   = [datetime]::ParseExact($matches[3], 'M/d/yyyy h:mm:ss tt', $null)
                FileVersion = $matches[4] -replace ', ', '.'
            }
        }
    }
    return $result
}

#If it exists, load a key value pair for Product:Version from a file.
                if (Test-Path $ProductVersionsPath) {
                                #load JSON into hash table
                                $ProductVersions = Read-KeyValuePairs -FilePath $ProductVersionsPath      
                }
 
#Get a list of all Roblox products
$products = $(Parse-RobloxManifest $((iwr $ManifestURL -usebasicparsing).content))
$products = $products | Sort-object -Property VersionHash -Unique |Sort-Object -property TimeStamp|where-object {$_.TimeStamp -gt $cutoffdate}

#For each Roblox product, get a list of all versions available.
foreach ($product in $products) {
                #If the product key doesn't exist yet, create it with a default value
                if (-not $ProductVersions.ContainsKey($product.ProductName)) {
                                $ProductVersions[$product.ProductName] = "0.0.0.0"
                                #write-host "$product is $($ProductVersions[$product.ProductName])"
                }
               
                #if version number is greater than the hashtable, then get the files/hashes
                $maxVersion = $ProductVersions[$product.ProductName]
                Write-Host "Working on $($($product.ProductName).padright(14)) - $($product.FileVersion) - $($product.Timestamp)"
 
                if ([version]$product.FileVersion -gt [version]$maxVersion){
                                $maxVersion = $product.FileVersion
                }
                if ([version]$product.FileVersion -gt [version]$($ProductVersions[$product.ProductName])){
                                $FileName = ""
                                if ($product.ProductName -eq "WindowsPlayer") {
                                                $Filenames = @("RobloxApp.zip","RobloxPlayerLauncher.exe")
                                } else {
                                                $Filenames = @("RobloxStudio.zip")
                                }
                                ForEach ($Filename in $Filenames) {
                                                $hashList = Get-7zSfxHashes -Url "$BaseURL$($product.VersionHash)-$Filename"

                                                #$hashlist
                                                foreach ($hash in $hashList){
                                                                $HashesFound[$hash] = "$ProductName $($product.ProductName) - $($product.FileVersion)"
                                                }
                                }              
                }
                $ProductVersions[$product.ProductName] = $maxVersion
}

#Write to the save file
Save-KeyValuePairs -Pairs $ProductVersions -FilePath $ProductVersionsPath
if ($HashesFound.count -eq 0) {
                write-host "No new Hashes found."
} else {
                write-host "Found $($HashesFound.count) new hashes."
                write-host "Writing Hashes to file $BasePath\$ProductName - Hashes - $CurrentDate.csv"
                $HashesFound.GetEnumerator() | Select-Object Key, Value | Export-Csv -Path "$BasePath\$ProductName - Hashes - $CurrentDate.csv" -NoTypeInformation -Force
}
