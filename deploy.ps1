<#
.SYNOPSIS
Deploys the serverless document processing pipeline to Google Cloud.

.DESCRIPTION
This script automates the provisioning of a Cloud Storage bucket, Pub/Sub topic, BigQuery dataset, and Cloud Run service.
It requires the Google Cloud SDK (gcloud) to be installed and authenticated.

.PARAMETER ProjectId
The Google Cloud Project ID. If not provided, the default project in gcloud config is used.

.PARAMETER Region
The Google Cloud Region to deploy resources into. Default is 'us-central1'.

.PARAMETER BucketName
The name of the Cloud Storage bucket to create. It must be globally unique. Default is 'doc-pipeline-upload-<random>'.
#>

param (
    [string]$ProjectId = $(gcloud config get-value project 2>$null),
    [string]$Region = "us-central1",
    [string]$BucketName = "doc-pipeline-upload-$((Get-Random -Minimum 10000 -Maximum 99999))"
)

# ErrorActionPreference is default (Continue) so native stderr doesn't halt the script
if (-not $ProjectId) {
    Write-Error "Could not determine Google Cloud Project ID. Please specify with -ProjectId."
    exit 1
}

$TopicName = "doc-upload-topic"
$SubName = "doc-upload-sub"
$ServiceName = "doc-processor"
$BqDataset = "document_pipeline"
$BqTable = "metadata"
$InvokerSaName = "pubsub-invoker"
$InvokerSaEmail = "$InvokerSaName@$ProjectId.iam.gserviceaccount.com"

Write-Host "====================================================="
Write-Host "Deploying Document Pipeline to Project: $ProjectId"
Write-Host "Region: $Region"
Write-Host "Bucket: $BucketName"
Write-Host "====================================================="

# 1. Enable APIs
Write-Host "`n[1/7] Enabling necessary Google Cloud APIs..."
gcloud services enable run.googleapis.com pubsub.googleapis.com storage.googleapis.com bigquery.googleapis.com cloudbuild.googleapis.com --project $ProjectId

# 2. BigQuery Setup
Write-Host "`n[2/7] Setting up BigQuery dataset and table..."
# Check if dataset exists
$datasetExists = bq show "$ProjectId`:$BqDataset" 2>$null
if (-not $datasetExists) {
    bq mk -d --location=$Region "$ProjectId`:$BqDataset"
    Write-Host "Created BigQuery dataset: $BqDataset"
} else {
    Write-Host "BigQuery dataset $BqDataset already exists."
}

# Check if table exists
$tableExists = bq show "$ProjectId`:$BqDataset.$BqTable" 2>$null
if (-not $tableExists) {
    bq mk -t --schema "filename:STRING,processing_date:TIMESTAMP,tags:STRING,word_count:INTEGER,bucket:STRING" "$ProjectId`:$BqDataset.$BqTable"
    Write-Host "Created BigQuery table: $BqTable"
} else {
    Write-Host "BigQuery table $BqTable already exists."
}

# 3. Create Cloud Storage Bucket
Write-Host "`n[3/7] Creating Cloud Storage bucket..."
$bucketExists = gcloud storage buckets describe "gs://$BucketName" --project $ProjectId 2>$null
if (-not $bucketExists) {
    gcloud storage buckets create "gs://$BucketName" --location=$Region --project $ProjectId
    Write-Host "Created bucket: gs://$BucketName"
} else {
    Write-Host "Bucket gs://$BucketName already exists."
}

# 4. Create Pub/Sub Topic and Notifications
Write-Host "`n[4/7] Creating Pub/Sub topic and linking to Storage..."
$topicExists = gcloud pubsub topics describe $TopicName --project $ProjectId 2>$null
if (-not $topicExists) {
    gcloud pubsub topics create $TopicName --project $ProjectId
    Write-Host "Created Pub/Sub topic: $TopicName"
} else {
    Write-Host "Pub/Sub topic $TopicName already exists."
}

# Give Storage service agent permission to publish to Pub/Sub
Write-Host "Granting Storage service account publish permissions..."
$ProjectNumber = gcloud projects describe $ProjectId --format="value(projectNumber)"
$StorageServiceAccount = "service-$ProjectNumber@gs-project-accounts.iam.gserviceaccount.com"
gcloud pubsub topics add-iam-policy-binding $TopicName --member="serviceAccount:$StorageServiceAccount" --role="roles/pubsub.publisher" --project $ProjectId > $null

# Create notification
Write-Host "Creating bucket notification..."
# It might already exist, so we catch errors
try {
    gcloud storage buckets notifications create "gs://$BucketName" --topic=$TopicName --event-types=OBJECT_FINALIZE --project $ProjectId 2>$null
    Write-Host "Bucket notification created."
} catch {
    Write-Host "Bucket notification might already exist, continuing..."
}

# 5. Create Service Account for Pub/Sub to invoke Cloud Run
Write-Host "`n[5/7] Creating Service Account for Pub/Sub invoker..."
$saExists = gcloud iam service-accounts describe $InvokerSaEmail --project $ProjectId 2>$null
if (-not $saExists) {
    gcloud iam service-accounts create $InvokerSaName --display-name="Pub/Sub Invoker" --project $ProjectId
    Write-Host "Created service account: $InvokerSaEmail"
} else {
    Write-Host "Service account $InvokerSaEmail already exists."
}

# 6. Build and Deploy Cloud Run Service
Write-Host "`n[6/7] Building and deploying Cloud Run service..."
gcloud run deploy $ServiceName `
    --source . `
    --region $Region `
    --project $ProjectId `
    --no-allow-unauthenticated `
    --quiet `
    --set-env-vars="PROJECT_ID=$ProjectId,BQ_DATASET=$BqDataset,BQ_TABLE=$BqTable"

$ServiceUrl = gcloud run services describe $ServiceName --region $Region --project $ProjectId --format="value(status.url)"
Write-Host "Cloud Run service deployed at: $ServiceUrl"

# Give invoker SA permission to invoke Cloud Run
Write-Host "Granting invoker SA permission to run service..."
gcloud run services add-iam-policy-binding $ServiceName `
    --region $Region `
    --project $ProjectId `
    --member="serviceAccount:$InvokerSaEmail" `
    --role="roles/run.invoker" > $null

# 7. Create Pub/Sub Push Subscription
Write-Host "`n[7/7] Creating Pub/Sub push subscription..."
$subExists = gcloud pubsub subscriptions describe $SubName --project $ProjectId 2>$null
if (-not $subExists) {
    gcloud pubsub subscriptions create $SubName `
        --topic=$TopicName `
        --push-endpoint="$ServiceUrl/" `
        --push-auth-service-account=$InvokerSaEmail `
        --project $ProjectId
    Write-Host "Created push subscription: $SubName"
} else {
    # If it exists, update it to point to the correct endpoint
    gcloud pubsub subscriptions update $SubName `
        --push-endpoint="$ServiceUrl/" `
        --push-auth-service-account=$InvokerSaEmail `
        --project $ProjectId
    Write-Host "Updated existing push subscription: $SubName"
}

Write-Host "`n====================================================="
Write-Host "Deployment Complete!"
Write-Host "You can test the pipeline by uploading a file to your bucket:"
Write-Host "  gcloud storage cp test_file.txt gs://$BucketName"
Write-Host "Then check BigQuery:"
Write-Host "  bq query --nouse_legacy_sql `"SELECT * FROM $ProjectId.$BqDataset.$BqTable`""
Write-Host "====================================================="
