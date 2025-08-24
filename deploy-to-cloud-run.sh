#!/bin/bash
# Deployment script for Odoo v18.0 to Google Cloud Run
# This script deploys both production and staging environments

set -e

# Configuration
PROJECT_ID="summit-paragliding"
REGION="us-central1"
DB_INSTANCE="summit-paragliding-db"
REPO_NAME="summit-paragliding-odoo"
SERVICE_ACCOUNT="odoo-cloud-run@${PROJECT_ID}.iam.gserviceaccount.com"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    echo_info "Checking prerequisites..."
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 > /dev/null; then
        echo_error "Not authenticated with gcloud. Run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        echo_error "Docker is not running. Please start Docker."
        exit 1
    fi
    
    echo_info "Prerequisites check passed!"
}

# Function to create service account if it doesn't exist
create_service_account() {
    echo_info "Creating service account for Cloud Run..."
    
    if ! gcloud iam service-accounts describe $SERVICE_ACCOUNT > /dev/null 2>&1; then
        gcloud iam service-accounts create odoo-cloud-run \
            --display-name="Odoo Cloud Run Service Account" \
            --description="Service account for Odoo running on Cloud Run"
    else
        echo_info "Service account already exists."
    fi
    
    # Grant necessary permissions
    echo_info "Granting permissions to service account..."
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SERVICE_ACCOUNT" \
        --role="roles/cloudsql.client"
    
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SERVICE_ACCOUNT" \
        --role="roles/secretmanager.secretAccessor"
}

# Function to build and push Docker image
build_and_push_image() {
    local TAG=$1
    local IMAGE_URL="gcr.io/${PROJECT_ID}/${REPO_NAME}:${TAG}"
    
    echo_info "Building Docker image for tag: $TAG"
    
    # Configure Docker for GCR
    gcloud auth configure-docker gcr.io --quiet
    
    # Build the image
    docker build -t $IMAGE_URL .
    
    # Push the image
    echo_info "Pushing image to Google Container Registry..."
    docker push $IMAGE_URL
    
    echo $IMAGE_URL
}

# Function to deploy to Cloud Run
deploy_to_cloud_run() {
    local ENV=$1  # prod or staging
    local IMAGE_URL=$2
    local DB_NAME="summit-paragliding-${ENV}"
    local SERVICE_NAME="summit-paragliding-odoo-${ENV}"
    local CUSTOM_ADDONS_BRANCH=""
    
    if [ "$ENV" = "staging" ]; then
        CUSTOM_ADDONS_BRANCH="staging"
    else
        CUSTOM_ADDONS_BRANCH="main"
    fi
    
    echo_info "Deploying $ENV environment to Cloud Run..."
    
    gcloud run deploy $SERVICE_NAME \
        --image=$IMAGE_URL \
        --platform=managed \
        --region=$REGION \
        --allow-unauthenticated \
        --service-account=$SERVICE_ACCOUNT \
        --memory=2Gi \
        --cpu=2 \
        --timeout=3600 \
        --concurrency=1000 \
        --min-instances=1 \
        --max-instances=10 \
        --set-env-vars="DB_HOST=/cloudsql/${PROJECT_ID}:${REGION}:${DB_INSTANCE}" \
        --set-env-vars="DB_NAME=${DB_NAME}" \
        --set-env-vars="DB_USER=odoo" \
        --set-env-vars="CUSTOM_ADDONS_REPO=https://github.com/Jay-Pel/Summit-Paragliding.git" \
        --set-env-vars="CUSTOM_ADDONS_BRANCH=${CUSTOM_ADDONS_BRANCH}" \
        --set-secrets="DB_PASSWORD=odoo-db-password:latest" \
        --set-secrets="ADMIN_PASSWORD=odoo-admin-password:latest" \
        --add-cloudsql-instances="${PROJECT_ID}:${REGION}:${DB_INSTANCE}" \
        --execution-environment=gen2
    
    # Get the service URL
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format='value(status.url)')
    echo_info "$ENV environment deployed successfully!"
    echo_info "Service URL: $SERVICE_URL"
    
    return 0
}

# Function to set up custom domain (optional)
setup_custom_domain() {
    local ENV=$1
    local DOMAIN=$2
    local SERVICE_NAME="summit-paragliding-odoo-${ENV}"
    
    if [ -n "$DOMAIN" ]; then
        echo_info "Setting up custom domain: $DOMAIN"
        gcloud run domain-mappings create \
            --service=$SERVICE_NAME \
            --domain=$DOMAIN \
            --region=$REGION
    fi
}

# Main deployment function
main() {
    local ENVIRONMENT=${1:-"both"}  # prod, staging, or both
    
    echo_info "Starting Odoo v18.0 deployment to Google Cloud Run"
    echo_info "Project: $PROJECT_ID"
    echo_info "Region: $REGION"
    echo_info "Environment: $ENVIRONMENT"
    
    # Check prerequisites
    check_prerequisites
    
    # Create service account
    create_service_account
    
    # Deploy based on environment
    case $ENVIRONMENT in
        "prod")
            IMAGE_URL=$(build_and_push_image "latest")
            deploy_to_cloud_run "prod" $IMAGE_URL
            ;;
        "staging")
            IMAGE_URL=$(build_and_push_image "staging")
            deploy_to_cloud_run "staging" $IMAGE_URL
            ;;
        "both"|*)
            # Deploy staging first
            IMAGE_URL_STAGING=$(build_and_push_image "staging")
            deploy_to_cloud_run "staging" $IMAGE_URL_STAGING
            
            # Deploy production
            IMAGE_URL_PROD=$(build_and_push_image "latest")
            deploy_to_cloud_run "prod" $IMAGE_URL_PROD
            ;;
    esac
    
    echo_info "Deployment completed successfully! 🎉"
    echo_info ""
    echo_info "Next steps:"
    echo_info "1. Create the Summit-Paragliding repository on GitHub (private)"
    echo_info "2. Add custom addons to the repository"
    echo_info "3. Configure domain names if needed"
    echo_info "4. Set up monitoring and alerts"
}

# Run the main function with all arguments
main "$@"
