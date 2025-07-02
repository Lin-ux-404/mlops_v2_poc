# GasUni MLOps v2 Project

This project demonstrates an end-to-end MLOps implementation using Azure Machine Learning and Azure DevOps pipelines. It includes infrastructure setup, model training, and deployment pipelines for both batch and online endpoints.

## Project Structure

```
├── config-infra-dev.yml         # Infrastructure configuration for dev environment
├── config-infra-prod.yml        # Infrastructure configuration for prod environment
├── deploy-azure-resources.ps1   # Script to deploy Azure resources
├── environment.yml              # Conda environment file
├── requirements.txt             # Python package requirements
├── data/                        # Sample data for model training and testing
├── data-science/                # Data science code (prep, train, evaluate, register)
└── mlops/                       # MLOps code for Azure ML and DevOps pipelines
```

## Getting Started

### Prerequisites

- Azure subscription
- Azure DevOps organization and project
- Git
- Python 3.8+
- PowerShell

## Setup Instructions

### 1. Local Environment Setup

```powershell
# Create and activate a virtual environment
python -m venv .venv
.\.venv\Scripts\Activate.ps1

# Install required packages
pip install -r requirements.txt
```

### 2. Azure Setup

#### 2.1 Authenticate with Azure

```powershell
# Log in to Azure CLI
az login
az account set --subscription <your-subscription-id>
```

#### 2.2 Configure Infrastructure Files (if needed)

Review and update the config files (config-infra-dev.yml and config-infra-prod.yml) if needed. Default settings are:

```yaml
# Default settings
ap_vm_image: ubuntu-20.04
namespace: gasunimlopsv2
postfix: 0001
location: eastus
enable_aml_computecluster: true
enable_monitoring: false
```

#### 2.3 Deploy Azure Resources

```powershell
# Deploy production environment
.\deploy-azure-resources.ps1 -Environment prod

# Or deploy both dev and prod environments
.\deploy-azure-resources.ps1 -Environment both
```

#### 2.4 Configure Azure ML Workspace Permissions

After deployment, set up appropriate role assignments in your Azure ML workspaces:

1. Navigate to your Azure ML workspace in the Azure portal
2. Go to Access control (IAM)
3. Assign the following roles to your user/service principal:
   - **AzureML Data Scientist**
   - **AzureML Compute Operator**

> **Note:** For more information on Azure ML roles, see [Manage roles in your workspace](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-assign-roles)

#### 2.5 Configure Container Registry and Storage Account

1. **Container Registry:** Grant ACRPull role to your compute resources
2. **Storage Account:** Configure appropriate access settings (for this POC set everything to public)

### 3. Azure DevOps Setup

#### 3.1 Set up Azure DevOps Repository

1. Create an organization in Azure DevOps and add a project
2. Initialize a Git repository and clone it to your local machine
3. Add this code to your repository:

```powershell
# Initialize git repository (if not already done)
git init
git add .
git commit -m "Initial commit"

# Create and switch to dev branch
git checkout -b dev

# Push to remote repository (replace with your repository URL)
git remote add origin <your-repository-url>
git push -u origin dev
```

#### 3.2 Configure Azure DevOps Service Connections

1. In Azure DevOps, go to **Project Settings > Service connections**
2. Create service connections for both environments:
   - Resource Group service connections (dev and prod)
   - Azure ML Workspace service connections (dev and prod)
3. Use the following naming convention (matching the config files):
   - `gasuni-mlopsv2-rg-sc-dev`
   - `gasuni-mlopsv2-aml-sc-dev`
   - `gasuni-mlopsv2-rg-sc-prod`
   - `gasuni-mlopsv2-aml-sc-prod`

#### 3.3 Set up Variable Groups

Go to Library inside Pipelines. Create variable groups DevVars and ProdVars with the following variables:
- resource_group
- workspace_name

#### 3.4 Create Azure DevOps Pipelines

To set up the CI/CD pipelines in Azure DevOps:

1. In Azure DevOps, navigate to **Pipelines** in the left sidebar
2. Click on **New pipeline**
3. Select **Azure Repos Git** as your code repository source
4. Select your repository from the list
5. Choose **Existing Azure Pipelines YAML file**
6. Select the branch (typically `dev` or `main`)
7. In the path dropdown, select one of the following pipeline files:
   - `/mlops/devops-pipelines/deploy-model-training-pipeline.yml` (for model training)
   - `/mlops/devops-pipelines/deploy-batch-endpoint-pipeline.yml` (for batch endpoint)
   - `/mlops/devops-pipelines/deploy-online-endpoint-pipeline.yml` (for online endpoint)
8. Click **Continue**
9. Review the pipeline YAML file
10. Click **Run** to save and run the pipeline, or **Save** to just save it

Repeat these steps for each pipeline you want to create. You'll typically want to set up the model training pipeline first, followed by the endpoint deployment pipelines.

#### 3.3 Set up Pipeline Variable

Edit the pipeline you just created. Add the following variables to the pipeline:
- subscription_id
- tenant_id
- location

## CI/CD Pipeline Workflow

### Development Workflow

1. Create feature branches from `dev` branch
2. Make changes and push to the feature branch
3. Create a pull request to merge into `dev`
4. After PR approval, merge to `dev` which triggers the dev pipeline
5. Resources are deployed to the dev environment

### Production Deployment

1. Create a pull request from `dev` to `main`
2. After thorough testing and PR approval, merge to `main`
3. This triggers the production pipeline and deploys to the production environment

## Common Issues and Troubleshooting

### Self-hosted Agent Requirements

You may need to set up a self-hosted agent for your Azure DevOps pipelines. Follow these steps:

1. Go to **Project Settings > Agent pools > Add pool**
2. Select "Self-hosted" and create a new pool
3. Download and configure the agent on your machine
4. Update your pipeline YAML files to use this agent pool
