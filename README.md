# 👁️ Gemin-Eye

Gemin-Eye is a cloud-native document processing dashboard that ingests Google Cloud Storage notifications via Pub/Sub, simulates OCR/metadata extraction, and streams document metadata into BigQuery for real-time exploration in a modern SvelteKit web UI.

---

## Features

- **Automated GCS Event Handling**: Listens for file upload events from Google Cloud Storage via Pub/Sub.
- **Metadata Extraction**: Simulates OCR; extracts and stores relevant metadata about each document (filename, tag, word count, etc.).
- **BigQuery Integration**: Pushes extracted metadata into a BigQuery table for analytics.
- **Dashboard Frontend**: 
  - Built with SvelteKit.
  - Dashboard view of all processed documents.
  - Search and filter by tags and filename.
  - Responsive, modern UI.

## Architecture

- **Backend**: `FastAPI` (Python) microservice (`app/main.py`)
  - POST `/`: Receives Pub/Sub push with GCS details, simulates OCR & metadata extraction.
  - GET `/health`: Health check.
  - Interacts with Google Cloud Storage & BigQuery.
- **Frontend**: `SvelteKit` app (`web/`)
  - Loads and displays document metadata from BigQuery.
  - Provides interactive filtering and real-time statistics.

## Getting Started

### 1. Prerequisites

- Python 3.9+
- Node.js 18+
- Google Cloud account with GCS and BigQuery enabled
- Google Cloud credentials set via environment or local `gcloud` authentication

### 2. Backend Setup (`app/`)

```sh
cd app
pip install -r requirements.txt
uvicorn main:app --reload
```

#### Required Environment Variables

| Variable      | Default            | Description              |
| ------------- | ------------------ | ------------------------ |
| `PROJECT_ID`  | *(from gcloud)*    | GCP Project ID           |
| `BQ_DATASET`  | `document_pipeline`| BigQuery Dataset name    |
| `BQ_TABLE`    | `metadata`         | BigQuery Table name      |

### 3. Frontend Setup (`web/`)

```sh
cd web
npm install
npm run dev # or npm run build && npm run preview
```

- The web UI loads metadata from BigQuery (ensure backend and BigQuery are accessible).
- Customize project, dataset, or table in `web/src/routes/+page.server.ts` as needed.

### 4. Deployment

- Use the top-level `Dockerfile` for containerization.
- Automation scripts: `setup.sh`, `deploy.ps1`.

### 5. Cloud Integration

- Subscribe a Pub/Sub Topic to your GCS bucket and point it to the backend URL.
- Ensure backend permissions for GCS and BigQuery access.
- BigQuery table schema should match:  
  - `filename: STRING`
  - `processing_date: STRING`
  - `tags: STRING (JSON array)`
  - `word_count: INTEGER`
  - `bucket: STRING`

## Project Structure

```
.
├── app/           # Python FastAPI backend, Pub/Sub & BigQuery logic
│   ├── main.py
│   └── requirements.txt
├── web/           # SvelteKit UI frontend
│   ├── src/
│   └── package.json
├── Dockerfile     # Backend containerization
├── setup.sh       # Bootstrap/deploy script
└── deploy.ps1     # PowerShell deployment script
```

---

## Acknowledgements

- [FastAPI](https://fastapi.tiangolo.com/)
- [SvelteKit](https://kit.svelte.dev/)
- [Google Cloud Storage](https://cloud.google.com/storage)
- [Google BigQuery](https://cloud.google.com/bigquery)
