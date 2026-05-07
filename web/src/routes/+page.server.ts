import type { PageServerLoad } from './$types';
import { BigQuery } from '@google-cloud/bigquery';

const PROJECT_ID = 'gemin-eye';
const BQ_DATASET = 'document_pipeline';
const BQ_TABLE = 'metadata';

interface DocumentRow {
	filename: string;
	processing_date: string;
	tags: string;
	word_count: number;
	bucket: string;
}

export const load: PageServerLoad = async () => {
	const bq = new BigQuery({ projectId: PROJECT_ID });

	const query = `
    SELECT filename, processing_date, tags, word_count, bucket
    FROM \`${PROJECT_ID}.${BQ_DATASET}.${BQ_TABLE}\`
    ORDER BY processing_date DESC
    LIMIT 1000
  `;

	try {
		const [rows] = await bq.query({ query, location: 'us-central1' });

		const documents: DocumentRow[] = (rows as Record<string, unknown>[]).map((row) => ({
			filename: String(row.filename ?? ''),
			processing_date: row.processing_date
				? new Date(row.processing_date as string | number | Date).toISOString()
				: '',
			tags: String(row.tags ?? '[]'),
			word_count: Number(row.word_count ?? 0),
			bucket: String(row.bucket ?? '')
		}));

		// Collect every unique tag across all documents
		const allTags = new Set<string>();
		for (const doc of documents) {
			try {
				const parsed: string[] = JSON.parse(doc.tags);
				parsed.forEach((t) => allTags.add(t));
			} catch {
				/* skip unparseable */
			}
		}

		return {
			documents,
			allTags: [...allTags].sort()
		};
	} catch (err) {
		console.error('BigQuery query failed:', err);
		return {
			documents: [],
			allTags: [],
			error: 'Failed to fetch data from BigQuery. Make sure you are authenticated via gcloud.'
		};
	}
};
