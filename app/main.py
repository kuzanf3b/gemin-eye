import base64
import json
import logging
from datetime import datetime
from typing import Dict, Any

from fastapi import FastAPI, Request, HTTPException
from google.cloud import storage
from google.cloud import bigquery
import os

app = FastAPI()

# Initialize GCP clients
# We initialize them outside the request handler to reuse the connection pool
storage_client = storage.Client()
bq_client = bigquery.Client()

# Environment variables
PROJECT_ID = os.environ.get("PROJECT_ID")
BQ_DATASET = os.environ.get("BQ_DATASET", "document_pipeline")
BQ_TABLE = os.environ.get("BQ_TABLE", "metadata")

logging.basicConfig(level=logging.INFO)

def simulate_ocr_and_extract_metadata(bucket_name: str, file_name: str) -> Dict[str, Any]:
    """
    Simulates downloading the file and performing OCR.
    Returns extracted metadata.
    """
    logging.info(f"Simulating processing for gs://{bucket_name}/{file_name}")
    
    # In a real scenario, we would download the file:
    # bucket = storage_client.bucket(bucket_name)
    # blob = bucket.blob(file_name)
    # content = blob.download_as_bytes()
    # text = perform_ocr(content)
    
    # Simulating metadata extraction
    word_count = len(file_name) * 100 # arbitrary logic for simulation
    tags = ["document", file_name.split(".")[-1] if "." in file_name else "unknown"]
    
    metadata = {
        "filename": file_name,
        "processing_date": datetime.utcnow().isoformat(),
        "tags": json.dumps(tags),  # Store as JSON string in BQ
        "word_count": word_count,
        "bucket": bucket_name
    }
    
    return metadata

def stream_to_bigquery(metadata: Dict[str, Any]):
    """Streams the extracted metadata to BigQuery."""
    if not PROJECT_ID:
        logging.warning("PROJECT_ID environment variable not set. Using default client project.")
    
    table_id = f"{bq_client.project}.{BQ_DATASET}.{BQ_TABLE}"
    
    # We ensure tags is a string if the table expects a string, or array if it expects array.
    # In our deployment script, we will create the table with tags as STRING (JSON).
    
    errors = bq_client.insert_rows_json(table_id, [metadata])
    if errors:
        logging.error(f"Encountered errors while inserting rows: {errors}")
        raise RuntimeError(f"BigQuery insertion failed: {errors}")
    else:
        logging.info(f"Successfully inserted metadata for {metadata['filename']} into {table_id}")

@app.post("/")
async def receive_pubsub_message(request: Request):
    """Receives a push message from Pub/Sub."""
    try:
        envelope = await request.json()
    except Exception as e:
        logging.error("Invalid JSON received")
        raise HTTPException(status_code=400, detail="Invalid JSON format")

    if not envelope:
        raise HTTPException(status_code=400, detail="Empty request body")

    pubsub_message = envelope.get("message")
    if not pubsub_message:
        raise HTTPException(status_code=400, detail="Missing 'message' field in Pub/Sub envelope")

    if isinstance(pubsub_message, dict) and "data" in pubsub_message:
        try:
            # Pub/Sub messages are base64-encoded
            message_data = base64.b64decode(pubsub_message["data"]).decode("utf-8")
            data_payload = json.loads(message_data)
        except Exception as e:
            logging.error(f"Failed to decode message data: {e}")
            raise HTTPException(status_code=400, detail="Invalid message data format")
        
        logging.info(f"Received data payload: {data_payload}")
        
        # Cloud Storage notifications have bucket and name in the payload
        bucket_name = data_payload.get("bucket")
        file_name = data_payload.get("name")
        
        if not bucket_name or not file_name:
            logging.warning(f"Ignored message, missing bucket or name: {data_payload}")
            return {"status": "ignored"}
        
        try:
            metadata = simulate_ocr_and_extract_metadata(bucket_name, file_name)
            stream_to_bigquery(metadata)
            return {"status": "success", "metadata": metadata}
        except Exception as e:
            logging.error(f"Error processing file {file_name}: {e}")
            # Returning 500 will cause Pub/Sub to retry the message
            raise HTTPException(status_code=500, detail=str(e))
    else:
        raise HTTPException(status_code=400, detail="Invalid Pub/Sub message format")

@app.get("/health")
def health_check():
    return {"status": "ok"}
