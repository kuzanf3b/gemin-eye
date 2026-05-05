#!/bin/bash
set -e

# Default variables
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
REGION="us-central1"
BUCKET_NAME="doc-pipeline-upload-$RANDOM$RANDOM"

# Process arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --project-id) PROJECT_ID="$2"; shift ;;
        --region) REGION="$2"; shift ;;
        --bucket-name) BUCKET_NAME="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$PROJECT_ID" ]; then
    echo "Error: Could not determine Google Cloud Project ID. Please specify with --project-id."
    exit 1
fi

TOPIC_NAME="doc-upload-topic"
SUB_NAME="doc-upload-sub"
SERVICE_NAME="doc-processor"
BQ_DATASET="document_pipeline"
BQ_TABLE="metadata"
INVOKER_SA_NAME="pubsub-invoker"
INVOKER_SA_EMAIL="$INVOKER_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

echo "====================================================="
echo "Deploying Document Pipeline to Project: $PROJECT_ID"
echo "Region: $REGION"
echo "Bucket: $BUCKET_NAME"
echo "====================================================="

# 1. Enable APIs
echo ""
echo "[1/8] Enabling necessary Google Cloud APIs..."
gcloud services enable run.googleapis.com pubsub.googleapis.com storage.googleapis.com bigquery.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project "$PROJECT_ID"

# Fetch project number for IAM bindings
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

# 2. Assign necessary roles to default service accounts for Cloud Run deployments and BigQuery inserts
echo ""
echo "[2/8] Ensuring default service accounts have required permissions..."
# Cloud Build SA
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$PROJECT_NUMBER@cloudbuild.gserviceaccount.com" \
    --role="roles/artifactregistry.writer" >/dev/null

# Compute Engine Default SA
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role="roles/artifactregistry.writer" >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role="roles/storage.admin" >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role="roles/bigquery.dataEditor" >/dev/null

# 3. BigQuery Setup
echo ""
echo "[3/8] Setting up BigQuery dataset and table..."
if ! bq show "$PROJECT_ID:$BQ_DATASET" >/dev/null 2>&1; then
    bq mk -d --location="$REGION" "$PROJECT_ID:$BQ_DATASET"
    echo "Created BigQuery dataset: $BQ_DATASET"
else
    echo "BigQuery dataset $BQ_DATASET already exists."
fi

if ! bq show "$PROJECT_ID:$BQ_DATASET.$BQ_TABLE" >/dev/null 2>&1; then
    bq mk -t --schema "filename:STRING,processing_date:TIMESTAMP,tags:STRING,word_count:INTEGER,bucket:STRING" "$PROJECT_ID:$BQ_DATASET.$BQ_TABLE"
    echo "Created BigQuery table: $BQ_TABLE"
else
    echo "BigQuery table $BQ_TABLE already exists."
fi

# 4. Create Cloud Storage Bucket
echo ""
echo "[4/8] Creating Cloud Storage bucket..."
if ! gcloud storage buckets describe "gs://$BUCKET_NAME" --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud storage buckets create "gs://$BUCKET_NAME" --location="$REGION" --project "$PROJECT_ID"
    echo "Created bucket: gs://$BUCKET_NAME"
else
    echo "Bucket gs://$BUCKET_NAME already exists."
fi

# 5. Create Pub/Sub Topic and Notifications
echo ""
echo "[5/8] Creating Pub/Sub topic and linking to Storage..."
if ! gcloud pubsub topics describe "$TOPIC_NAME" --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud pubsub topics create "$TOPIC_NAME" --project "$PROJECT_ID"
    echo "Created Pub/Sub topic: $TOPIC_NAME"
else
    echo "Pub/Sub topic $TOPIC_NAME already exists."
fi

# Initialize Storage Service Agent if it doesn't exist
gcloud storage service-agent --project="$PROJECT_ID" >/dev/null 2>&1 || true

# Grant Storage service account publish permissions
echo "Granting Storage service account publish permissions..."
STORAGE_SA="service-$PROJECT_NUMBER@gs-project-accounts.iam.gserviceaccount.com"
gcloud pubsub topics add-iam-policy-binding "$TOPIC_NAME" \
    --member="serviceAccount:$STORAGE_SA" \
    --role="roles/pubsub.publisher" \
    --project "$PROJECT_ID" >/dev/null

# Create bucket notification
echo "Creating bucket notification..."
if ! gcloud storage buckets notifications list "gs://$BUCKET_NAME" --project "$PROJECT_ID" 2>/dev/null | grep -q "$TOPIC_NAME"; then
    gcloud storage buckets notifications create "gs://$BUCKET_NAME" --topic="$TOPIC_NAME" --event-types=OBJECT_FINALIZE --project "$PROJECT_ID" || echo "Notification might already exist."
else
    echo "Bucket notification already exists."
fi

# 6. Create Service Account for Pub/Sub to invoke Cloud Run
echo ""
echo "[6/8] Creating Service Account for Pub/Sub invoker..."
if ! gcloud iam service-accounts describe "$INVOKER_SA_EMAIL" --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud iam service-accounts create "$INVOKER_SA_NAME" --display-name="Pub/Sub Invoker" --project "$PROJECT_ID"
    echo "Created service account: $INVOKER_SA_EMAIL"
else
    echo "Service account $INVOKER_SA_EMAIL already exists."
fi

# 7. Build and Deploy Cloud Run Service
echo ""
echo "[7/8] Building and deploying Cloud Run service..."
gcloud run deploy "$SERVICE_NAME" \
    --source . \
    --region "$REGION" \
    --project "$PROJECT_ID" \
    --no-allow-unauthenticated \
    --quiet \
    --set-env-vars="PROJECT_ID=$PROJECT_ID,BQ_DATASET=$BQ_DATASET,BQ_TABLE=$BQ_TABLE"

SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --region "$REGION" --project "$PROJECT_ID" --format="value(status.url)")
echo "Cloud Run service deployed at: $SERVICE_URL"

# Grant invoker SA permission to invoke Cloud Run
echo "Granting invoker SA permission to run service..."
gcloud run services add-iam-policy-binding "$SERVICE_NAME" \
    --region "$REGION" \
    --project "$PROJECT_ID" \
    --member="serviceAccount:$INVOKER_SA_EMAIL" \
    --role="roles/run.invoker" >/dev/null

# 8. Create Pub/Sub Push Subscription
echo ""
echo "[8/8] Creating Pub/Sub push subscription..."
if ! gcloud pubsub subscriptions describe "$SUB_NAME" --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud pubsub subscriptions create "$SUB_NAME" \
        --topic="$TOPIC_NAME" \
        --push-endpoint="${SERVICE_URL}/" \
        --push-auth-service-account="$INVOKER_SA_EMAIL" \
        --project "$PROJECT_ID"
    echo "Created push subscription: $SUB_NAME"
else
    gcloud pubsub subscriptions update "$SUB_NAME" \
        --push-endpoint="${SERVICE_URL}/" \
        --push-auth-service-account="$INVOKER_SA_EMAIL" \
        --project "$PROJECT_ID"
    echo "Updated existing push subscription: $SUB_NAME"
fi

echo ""
echo "====================================================="
echo "Deployment Complete!"
echo "You can test the pipeline by uploading a file to your bucket:"
echo "  gcloud storage cp test_file.txt gs://$BUCKET_NAME"
echo "Then check BigQuery:"
echo "  bq query --nouse_legacy_sql \"SELECT * FROM $PROJECT_ID.$BQ_DATASET.$BQ_TABLE\""
echo "====================================================="
