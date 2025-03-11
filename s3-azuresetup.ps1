#!/usr/bin/env pwsh

# azure_s3_setup.ps1
# This script sets up an Azure Blob Storage account for S3 API compatibility
# and retrieves the necessary information for Portainer backups

# Default values
$defaultStorageAccount = "spoonubuntublob01"
$defaultResourceGroup = "ubuntu-podman_group"
$defaultBucketName = "portainer-backup"
$defaultLocation = "eastus"

function Test-AzureConnection {
    try {
        $context = Get-AzContext -ErrorAction Stop
        if ($null -eq $context.Account) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Connect-ToAzure {
    if (-not (Test-AzureConnection)) {
        Write-Host "Connecting to Azure..." -ForegroundColor Yellow
        try {
            Connect-AzAccount -ErrorAction Stop
            Write-Host "Successfully connected to Azure." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to connect to Azure: $_"
            exit 1
        }
    }
    else {
        Write-Host "Already connected to Azure as $((Get-AzContext).Account.Id)" -ForegroundColor Green
    }
}

function Get-UserInput {
    $choice = Read-Host "Do you want to create a new storage account or update an existing one? (C)reate/(U)pdate [U]"
    if ([string]::IsNullOrEmpty($choice) -or $choice.ToLower() -eq "u") {
        return "Update"
    }
    elseif ($choice.ToLower() -eq "c") {
        return "Create"
    }
    else {
        Write-Host "Invalid choice. Defaulting to Update." -ForegroundColor Yellow
        return "Update"
    }
}

function Get-StorageAccountDetails {
    $storageAccount = Read-Host "Enter storage account name [$defaultStorageAccount]"
    if ([string]::IsNullOrEmpty($storageAccount)) {
        $storageAccount = $defaultStorageAccount
    }

    $resourceGroup = Read-Host "Enter resource group name [$defaultResourceGroup]"
    if ([string]::IsNullOrEmpty($resourceGroup)) {
        $resourceGroup = $defaultResourceGroup
    }

    $bucketName = Read-Host "Enter bucket (container) name [$defaultBucketName]"
    if ([string]::IsNullOrEmpty($bucketName)) {
        $bucketName = $defaultBucketName
    }

    return @{
        StorageAccount = $storageAccount
        ResourceGroup = $resourceGroup
        BucketName = $bucketName
    }
}

function Create-StorageAccount {
    param (
        [string]$StorageAccount,
        [string]$ResourceGroup,
        [string]$BucketName
    )

    # Check if resource group exists, create if it doesn't
    $rgExists = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue
    if (-not $rgExists) {
        $location = Read-Host "Resource group doesn't exist. Enter location for new resource group [$defaultLocation]"
        if ([string]::IsNullOrEmpty($location)) {
            $location = $defaultLocation
        }
        New-AzResourceGroup -Name $ResourceGroup -Location $location -ErrorAction Stop
        Write-Host "Resource group $ResourceGroup created in $location" -ForegroundColor Green
    }

    # Check if storage account exists
    $saExists = Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageAccount -ErrorAction SilentlyContinue
    if (-not $saExists) {
        Write-Host "Creating storage account $StorageAccount..." -ForegroundColor Yellow
        
        $location = if ($rgExists) { (Get-AzResourceGroup -Name $ResourceGroup).Location } else { $location }
        
        # Create storage account with hierarchical namespace enabled and support for S3 API
        $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroup `
            -Name $StorageAccount `
            -Location $location `
            -SkuName Standard_LRS `
            -Kind StorageV2 `
            -EnableHttpsTrafficOnly $true `
            -AllowBlobPublicAccess $false

        # Enable S3 compatible API
        Set-AzStorageAccount -ResourceGroupName $ResourceGroup `
            -Name $StorageAccount `
            -EnableHttpsTrafficOnly $true `
            -MinimumTlsVersion TLS1_2
    }
    else {
        Write-Host "Storage account $StorageAccount already exists." -ForegroundColor Green
    }
    
    # Create container if it doesn't exist
    $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
    $context = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $storageAccountKey
    
    $containerExists = Get-AzStorageContainer -Name $BucketName -Context $context -ErrorAction SilentlyContinue
    if (-not $containerExists) {
        New-AzStorageContainer -Name $BucketName -Context $context -Permission Off
        Write-Host "Container (bucket) $BucketName created." -ForegroundColor Green
    }
    else {
        Write-Host "Container (bucket) $BucketName already exists." -ForegroundColor Green
    }
    
    return $context
}

function Update-StorageAccount {
    param (
        [string]$StorageAccount,
        [string]$ResourceGroup,
        [string]$BucketName
    )
    
    # Check if storage account exists
    $saExists = Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageAccount -ErrorAction SilentlyContinue
    if (-not $saExists) {
        Write-Host "Storage account $StorageAccount does not exist in resource group $ResourceGroup." -ForegroundColor Red
        $createNew = Read-Host "Do you want to create it? (Y/N) [Y]"
        if ([string]::IsNullOrEmpty($createNew) -or $createNew.ToLower() -eq "y") {
            return Create-StorageAccount -StorageAccount $StorageAccount -ResourceGroup $ResourceGroup -BucketName $BucketName
        }
        else {
            exit 1
        }
    }
    
    # Update storage account settings for S3 compatibility
    Write-Host "Updating storage account settings..." -ForegroundColor Yellow
    Set-AzStorageAccount -ResourceGroupName $ResourceGroup `
        -Name $StorageAccount `
        -EnableHttpsTrafficOnly $true `
        -MinimumTlsVersion TLS1_2

    # Create container if it doesn't exist
    $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
    $context = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $storageAccountKey
    
    $containerExists = Get-AzStorageContainer -Name $BucketName -Context $context -ErrorAction SilentlyContinue
    if (-not $containerExists) {
        New-AzStorageContainer -Name $BucketName -Context $context -Permission Off
        Write-Host "Container (bucket) $BucketName created." -ForegroundColor Green
    }
    else {
        Write-Host "Container (bucket) $BucketName already exists." -ForegroundColor Green
    }
    
    return $context
}

function Get-S3CompatibleInfo {
    param (
        [string]$StorageAccount,
        [string]$ResourceGroup,
        [string]$BucketName,
        [object]$Context
    )
    
    # Get storage account keys
    $keys = Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount
    $accessKey = $storageAccount
    $secretKey = $keys[0].Value
    
    # Get region from storage account
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageAccount
    $region = $storageAccount.Location
    
    # Build S3 compatible host
    $s3Host = "https://$StorageAccount.blob.core.windows.net"
    
    # Return information
    return @{
        AccessKeyID = $accessKey
        SecretAccessKey = $secretKey
        Region = $region
        BucketName = $BucketName
        S3CompatibleHost = $s3Host
    }
}

function Display-S3Info {
    param (
        [hashtable]$S3Info
    )
    
    Write-Host "`n=========== S3 API Information for Portainer Backups ===========" -ForegroundColor Cyan
    Write-Host "Access Key ID:           $($S3Info.AccessKeyID)" -ForegroundColor Green
    Write-Host "Secret Access Key:       $($S3Info.SecretAccessKey)" -ForegroundColor Green
    Write-Host "Region:                  $($S3Info.Region)" -ForegroundColor Green
    Write-Host "Bucket Name:             $($S3Info.BucketName)" -ForegroundColor Green
    Write-Host "S3 Compatible Host:      $($S3Info.S3CompatibleHost)" -ForegroundColor Green
    Write-Host "==============================================================" -ForegroundColor Cyan
}

# Main script execution
try {
    # Step 1: Connect to Azure
    Connect-ToAzure
    
    # Step 2: Get user choices
    $action = Get-UserInput
    $details = Get-StorageAccountDetails
    
    # Step 3: Create or update the storage account
    $context = $null
    if ($action -eq "Create") {
        $context = Create-StorageAccount -StorageAccount $details.StorageAccount -ResourceGroup $details.ResourceGroup -BucketName $details.BucketName
    }
    else {
        $context = Update-StorageAccount -StorageAccount $details.StorageAccount -ResourceGroup $details.ResourceGroup -BucketName $details.BucketName
    }
    
    # Step 4: Get and display S3 compatible information
    $s3Info = Get-S3CompatibleInfo -StorageAccount $details.StorageAccount -ResourceGroup $details.ResourceGroup -BucketName $details.BucketName -Context $context
    Display-S3Info -S3Info $s3Info
}
catch {
    Write-Error "An error occurred: $_"
    exit 1
}
