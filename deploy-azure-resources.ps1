#!/usr/bin/env pwsh
# deploy-azure-resources.ps1
# Script to deploy Azure infrastructure for MLOps project

param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "prod", "both")]
    [string] $Environment = "dev"
)

# Show execution progress
$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"
Set-StrictMode -Version Latest

# -----------------------------------------------------------------------------
# Login to Azure
# -----------------------------------------------------------------------------
Write-Host "Logging in to Azure..." -ForegroundColor Cyan
az account show 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    az login
}

# Show available subscriptions
Write-Host "Available subscriptions:" -ForegroundColor Yellow
az account list --query "[].{Name:name, SubscriptionId:id, Default:isDefault}" -o table

# Prompt for subscription selection
$subscription = Read-Host "Enter your subscription ID (or press Enter to use the default)"
if ($subscription) {
    Write-Host "Setting subscription to $subscription..." -ForegroundColor Cyan
    az account set --subscription $subscription
}

# Confirm current subscription
$currentSub = az account show --query "{Name:name, SubscriptionId:id}" -o json | ConvertFrom-Json
Write-Host "Using subscription: $($currentSub.Name) ($($currentSub.SubscriptionId))" -ForegroundColor Green

# -----------------------------------------------------------------------------
# Helper function to deploy an environment
# -----------------------------------------------------------------------------
function Deploy-Environment {
    param (
        [Parameter(Mandatory = $true)]
        [string] $EnvName
    )
    
    Write-Host "`n===================================================" -ForegroundColor Cyan
    Write-Host "Deploying $EnvName environment" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Cyan

    # -----------------------------------------------------------------------------
    # Extract variables from config file
    # -----------------------------------------------------------------------------
    $configFileName = "config-infra-$EnvName.yml"
    Write-Host "`nLoading configuration from $configFileName..." -ForegroundColor Cyan

    # Load config from YAML
    $configPath = Join-Path $PSScriptRoot $configFileName
    $config = Get-Content $configPath -Raw

    # Extract key variables using regex
    $namespace = if ($config -match 'namespace:\s*([^\s#]+)') { $matches[1] } else { "gasunimlopsv2" }
    $location = if ($config -match 'location:\s*([^\s#]+)') { $matches[1] } else { "eastus" }
    $environment = if ($config -match 'environment:\s*([^\s#]+)') { $matches[1] } else { $EnvName }

    # Build resource names
    $resourceGroup = "rg-${namespace}-${environment}"
    $amlWorkspace = "mlw-${namespace}-${environment}"
    $keyVault = "kv${namespace}${environment}"
    $containerRegistry = "cr${namespace}${environment}"
    $storageAccount = "st${namespace}${environment}"
    $appInsights = "mlw${namespace}${environment}"

    # Terraform backend resources
    $terraformResourceGroup = "rg-${namespace}-${environment}-tf"
    $terraformStorageAccount = "st${namespace}${environment}tf"
    $terraformContainer = "default"

    # -----------------------------------------------------------------------------
    # Deploy resources
    # -----------------------------------------------------------------------------
    Write-Host "`nDeploying Azure resources with the following configuration:" -ForegroundColor Cyan
    Write-Host "  Resource Group:      $resourceGroup" -ForegroundColor Yellow
    Write-Host "  Location:            $location" -ForegroundColor Yellow
    Write-Host "  AML Workspace:       $amlWorkspace" -ForegroundColor Yellow
    Write-Host "  Key Vault:           $keyVault" -ForegroundColor Yellow
    Write-Host "  Container Registry:  $containerRegistry" -ForegroundColor Yellow
    Write-Host "  Storage Account:     $storageAccount" -ForegroundColor Yellow
    Write-Host "  App Insights:        $appInsights" -ForegroundColor Yellow

    $confirm = Read-Host "Continue with deployment of $EnvName environment? (y/n)"
    if ($confirm -ne "y") {
        Write-Host "Deployment cancelled for $EnvName environment." -ForegroundColor Red
        return
    }

    # Create resource group
    Write-Host "`nCreating resource group..." -ForegroundColor Cyan
    az group create --name $resourceGroup --location $location

    # Create storage account
    Write-Host "`nCreating storage account..." -ForegroundColor Cyan
    az storage account create `
      --name $storageAccount `
      --resource-group $resourceGroup `
      --location $location `
      --sku Standard_LRS `
      --kind StorageV2 `
      --https-only true

    # Create container registry
    Write-Host "`nCreating container registry..." -ForegroundColor Cyan
    az acr create `
      --name $containerRegistry `
      --resource-group $resourceGroup `
      --location $location `
      --sku Standard

    # Create key vault
    Write-Host "`nCreating key vault..." -ForegroundColor Cyan
    az keyvault create `
      --name $keyVault `
      --resource-group $resourceGroup `
      --location $location

    # Create Application Insights
    Write-Host "`nCreating Application Insights..." -ForegroundColor Cyan
    az monitor app-insights component create `
      --app $appInsights `
      --location $location `
      --resource-group $resourceGroup

    # Create Azure ML workspace
    Write-Host "`nCreating Azure ML workspace..." -ForegroundColor Cyan

    # Get resource IDs for the associated resources
    Write-Host "Getting resource IDs for associated resources..." -ForegroundColor Cyan
    $storageAccountId = az storage account show --name $storageAccount --resource-group $resourceGroup --query id -o tsv
    $keyVaultId = az keyvault show --name $keyVault --resource-group $resourceGroup --query id -o tsv
    $containerRegistryId = az acr show --name $containerRegistry --resource-group $resourceGroup --query id -o tsv
    $appInsightsId = az monitor app-insights component show --app $appInsights --resource-group $resourceGroup --query id -o tsv

    Write-Host "Creating AML workspace with resource IDs..." -ForegroundColor Cyan
    az ml workspace create `
      --name $amlWorkspace `
      --resource-group $resourceGroup `
      --location $location `
      --storage-account $storageAccountId `
      --key-vault $keyVaultId `
      --container-registry $containerRegistryId `
      --application-insights $appInsightsId

    # Create compute cluster
    Write-Host "`nCreating compute cluster..." -ForegroundColor Cyan
    az ml compute create `
      --name cpu-cluster `
      --type amlcompute `
      --size Standard_DS3_v2 `
      --min-instances 0 `
      --max-instances 2 `
      --tier low_priority `
      --resource-group $resourceGroup `
      --workspace-name $amlWorkspace

    # Create batch compute cluster
    Write-Host "`nCreating batch compute cluster..." -ForegroundColor Cyan
    az ml compute create `
      --name batch-cluster `
      --type amlcompute `
      --size Standard_DS3_v2 `
      --min-instances 0 `
      --max-instances 5 `
      --tier dedicated `
      --resource-group $resourceGroup `
      --workspace-name $amlWorkspace

    # -----------------------------------------------------------------------------
    # Create Terraform backend resources (for future use)
    # -----------------------------------------------------------------------------
    Write-Host "`nCreating Terraform backend resources..." -ForegroundColor Cyan
    Write-Host "  Resource Group:      $terraformResourceGroup" -ForegroundColor Yellow
    Write-Host "  Storage Account:     $terraformStorageAccount" -ForegroundColor Yellow
    Write-Host "  Container:           $terraformContainer" -ForegroundColor Yellow

    # Create resource group for Terraform state
    az group create --name $terraformResourceGroup --location $location

    # Create storage account for Terraform state
    az storage account create `
      --name $terraformStorageAccount `
      --resource-group $terraformResourceGroup `
      --location $location `
      --sku Standard_LRS `
      --kind StorageV2 `
      --https-only true

    # Create container for Terraform state
    az storage container create `
      --name $terraformContainer `
      --account-name $terraformStorageAccount

    # -----------------------------------------------------------------------------
    # Create config.json for Azure ML SDK
    # -----------------------------------------------------------------------------
    Write-Host "`nCreating config.json for Azure ML SDK..." -ForegroundColor Cyan
    $subscriptionId = az account show --query id -o tsv
    $configJson = @{
      subscription_id = $subscriptionId
      resource_group = $resourceGroup
      workspace_name = $amlWorkspace
    } | ConvertTo-Json

    $configJsonPath = Join-Path $PSScriptRoot "config-$EnvName.json"
    $configJson | Out-File -FilePath $configJsonPath -Encoding UTF8
    Write-Host "Created config.json at $configJsonPath" -ForegroundColor Green

    # -----------------------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------------------
    Write-Host "`nDeployment of $EnvName environment completed successfully!" -ForegroundColor Green
    Write-Host "`nResources deployed:" -ForegroundColor Cyan
    Write-Host "  Resource Group:      $resourceGroup" -ForegroundColor Yellow
    Write-Host "  AML Workspace:       $amlWorkspace" -ForegroundColor Yellow
    Write-Host "  Key Vault:           $keyVault" -ForegroundColor Yellow
    Write-Host "  Container Registry:  $containerRegistry" -ForegroundColor Yellow
    Write-Host "  Storage Account:     $storageAccount" -ForegroundColor Yellow
    Write-Host "  App Insights:        $appInsights" -ForegroundColor Yellow
    Write-Host "  Compute Clusters:    cpu-cluster, batch-cluster" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# Main execution starts here
# -----------------------------------------------------------------------------

# Check which environment(s) to deploy
if ($Environment -eq "both" -or $Environment -eq "dev") {
    Deploy-Environment -EnvName "dev"
}

if ($Environment -eq "both" -or $Environment -eq "prod") {
    Deploy-Environment -EnvName "prod"
}

# -----------------------------------------------------------------------------
# Final summary
# -----------------------------------------------------------------------------
Write-Host "`n===================================================" -ForegroundColor Green
Write-Host "Deployment process completed!" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Set up service connections in Azure DevOps:" -ForegroundColor Yellow
Write-Host "   - Service connection for resource group: gasuni-mlopsv2-rg-sc" -ForegroundColor Yellow
Write-Host "   - Service connection for AML workspace: gasuni-mlopsv2-aml-sc" -ForegroundColor Yellow
Write-Host "2. Configure Azure DevOps pipelines:" -ForegroundColor Yellow
Write-Host "   - deploy-model-training-pipeline.yml" -ForegroundColor Yellow
Write-Host "   - deploy-online-endpoint-pipeline.yml" -ForegroundColor Yellow
Write-Host "   - deploy-batch-endpoint-pipeline.yml" -ForegroundColor Yellow
Write-Host "3. Run the model training pipeline to train and register your model" -ForegroundColor Yellow
Write-Host "4. Deploy your model to online and batch endpoints" -ForegroundColor Yellow

Write-Host "`nTo run Azure ML operations locally:" -ForegroundColor Cyan
if ($Environment -eq "both" -or $Environment -eq "dev") {
    Write-Host "- For DEV environment, use the generated config-dev.json file" -ForegroundColor Yellow
}
if ($Environment -eq "both" -or $Environment -eq "prod") {
    Write-Host "- For PROD environment, use the generated config-prod.json file" -ForegroundColor Yellow
}
