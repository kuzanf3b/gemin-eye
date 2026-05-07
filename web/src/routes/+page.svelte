<script lang="ts">
	let { data } = $props();

	let searchQuery = $state('');
	let activeTag = $state('');

	const filteredDocs = $derived(() => {
		let docs = data.documents;

		// Filter by active tag
		if (activeTag) {
			docs = docs.filter((d) => {
				try {
					const tags: string[] = JSON.parse(d.tags);
					return tags.includes(activeTag);
				} catch {
					return false;
				}
			});
		}

		// Filter by search query
		if (searchQuery.trim()) {
			const q = searchQuery.toLowerCase();
			docs = docs.filter((d) => d.filename.toLowerCase().includes(q));
		}

		return docs;
	});

	function parseTags(raw: string): string[] {
		try {
			return JSON.parse(raw);
		} catch {
			return [];
		}
	}

	function formatDate(iso: string): string {
		if (!iso) return '—';
		const d = new Date(iso);
		return d.toLocaleDateString('en-US', {
			year: 'numeric',
			month: 'short',
			day: 'numeric',
			hour: '2-digit',
			minute: '2-digit'
		});
	}

	function toggleTag(tag: string) {
		activeTag = activeTag === tag ? '' : tag;
	}
</script>

<div class="shell">
	<!-- Header -->
	<header class="header" id="app-header">
		<div class="header-inner">
			<div class="brand">
				<svg class="brand-icon" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
					<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
					<polyline points="14 2 14 8 20 8" />
					<line x1="16" y1="13" x2="8" y2="13" />
					<line x1="16" y1="17" x2="8" y2="17" />
					<polyline points="10 9 9 9 8 9" />
				</svg>
				<div>
					<h1 class="brand-title">Gemin-Eye</h1>
					<p class="brand-subtitle">Document Processing Dashboard</p>
				</div>
			</div>

			<div class="stats-row">
				<div class="stat" id="stat-total">
					<span class="stat-value">{data.documents.length}</span>
					<span class="stat-label">Documents</span>
				</div>
				<div class="stat-divider"></div>
				<div class="stat" id="stat-tags">
					<span class="stat-value">{data.allTags.length}</span>
					<span class="stat-label">Tags</span>
				</div>
				<div class="stat-divider"></div>
				<div class="stat" id="stat-shown">
					<span class="stat-value">{filteredDocs().length}</span>
					<span class="stat-label">Showing</span>
				</div>
			</div>
		</div>
	</header>

	<main class="main">
		<!-- Error Banner -->
		{#if data.error}
			<div class="error-banner" id="error-banner" role="alert">
				<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
					<circle cx="12" cy="12" r="10" />
					<line x1="12" y1="8" x2="12" y2="12" />
					<line x1="12" y1="16" x2="12.01" y2="16" />
				</svg>
				<span>{data.error}</span>
			</div>
		{/if}

		<!-- Controls -->
		<section class="controls" id="controls-section">
			<!-- Search -->
			<div class="search-box" id="search-box">
				<svg class="search-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
					<circle cx="11" cy="11" r="8" />
					<line x1="21" y1="21" x2="16.65" y2="16.65" />
				</svg>
				<input
					type="text"
					id="search-input"
					class="search-input"
					placeholder="Search by filename…"
					bind:value={searchQuery}
				/>
				{#if searchQuery}
					<button class="search-clear" onclick={() => (searchQuery = '')} aria-label="Clear search">
						<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<line x1="18" y1="6" x2="6" y2="18" />
							<line x1="6" y1="6" x2="18" y2="18" />
						</svg>
					</button>
				{/if}
			</div>

			<!-- Tag Filters -->
			{#if data.allTags.length > 0}
				<div class="tag-filters" id="tag-filters">
					<span class="tag-label">Filter by tag:</span>
					<div class="tag-list">
						{#each data.allTags as tag (tag)}
							<button
								class="tag-chip"
								class:active={activeTag === tag}
								onclick={() => toggleTag(tag)}
								id="tag-{tag}"
							>
								{tag}
							</button>
						{/each}
						{#if activeTag}
							<button class="tag-clear" onclick={() => (activeTag = '')} id="tag-clear-btn">
								Clear filter
							</button>
						{/if}
					</div>
				</div>
			{/if}
		</section>

		<!-- Table -->
		<section class="table-section" id="documents-table-section">
			{#if filteredDocs().length === 0}
				<div class="empty-state" id="empty-state">
					<svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--color-empty)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
						<path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z" />
						<polyline points="13 2 13 9 20 9" />
					</svg>
					<p class="empty-title">No documents found</p>
					<p class="empty-subtitle">
						{#if searchQuery || activeTag}
							Try adjusting your search or filter.
						{:else}
							Upload a file to your Cloud Storage bucket to get started.
						{/if}
					</p>
				</div>
			{:else}
				<div class="table-wrap">
					<table class="table" id="documents-table">
						<thead>
							<tr>
								<th class="th-filename">Filename</th>
								<th class="th-date">Upload Date</th>
								<th class="th-tags">Tags</th>
								<th class="th-words">Word Count</th>
							</tr>
						</thead>
						<tbody>
							{#each filteredDocs() as doc, i (doc.filename + doc.processing_date + i)}
								<tr class="table-row" style="animation-delay: {i * 25}ms">
									<td class="cell-filename">
										<svg class="file-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
											<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
											<polyline points="14 2 14 8 20 8" />
										</svg>
										<span>{doc.filename}</span>
									</td>
									<td class="cell-date">{formatDate(doc.processing_date)}</td>
									<td class="cell-tags">
										{#each parseTags(doc.tags) as tag (tag)}
											<span
												class="inline-tag"
												class:highlight={activeTag === tag}
												role="button"
												tabindex="0"
												onclick={() => toggleTag(tag)}
												onkeydown={(e) => e.key === 'Enter' && toggleTag(tag)}
											>{tag}</span>
										{/each}
									</td>
									<td class="cell-words">
										<span class="word-count">{doc.word_count.toLocaleString()}</span>
									</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		</section>
	</main>
</div>

<style>
	/* Shell */
	.shell {
		min-height: 100vh;
		display: flex;
		flex-direction: column;
	}

	/* Header */
	.header {
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border);
		position: sticky;
		top: 0;
		z-index: 10;
	}
	.header-inner {
		max-width: 1200px;
		margin: 0 auto;
		padding: var(--space-5) var(--space-6);
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-6);
	}
	.brand {
		display: flex;
		align-items: center;
		gap: var(--space-3);
	}
	.brand-icon {
		color: var(--color-accent);
		flex-shrink: 0;
	}
	.brand-title {
		font-size: var(--font-size-lg);
		font-weight: 700;
		letter-spacing: -0.02em;
		line-height: 1.2;
	}
	.brand-subtitle {
		font-size: var(--font-size-xs);
		color: var(--color-text-muted);
		font-weight: 500;
		letter-spacing: 0.01em;
	}

	/* Stats */
	.stats-row {
		display: flex;
		align-items: center;
		gap: var(--space-5);
	}
	.stat {
		text-align: center;
	}
	.stat-value {
		display: block;
		font-size: var(--font-size-lg);
		font-weight: 700;
		color: var(--color-text-primary);
		line-height: 1.2;
	}
	.stat-label {
		font-size: var(--font-size-xs);
		color: var(--color-text-muted);
		font-weight: 500;
	}
	.stat-divider {
		width: 1px;
		height: 28px;
		background: var(--color-border);
	}

	/* Main */
	.main {
		max-width: 1200px;
		margin: 0 auto;
		padding: var(--space-6);
		width: 100%;
		flex: 1;
	}

	/* Error */
	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		background: #fef2f2;
		border: 1px solid #fecaca;
		color: #b91c1c;
		padding: var(--space-3) var(--space-4);
		border-radius: var(--radius-md);
		font-size: var(--font-size-sm);
		margin-bottom: var(--space-6);
	}

	/* Controls */
	.controls {
		margin-bottom: var(--space-6);
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}

	/* Search */
	.search-box {
		position: relative;
		max-width: 400px;
	}
	.search-icon {
		position: absolute;
		left: var(--space-3);
		top: 50%;
		transform: translateY(-50%);
		color: var(--color-text-muted);
		pointer-events: none;
	}
	.search-input {
		width: 100%;
		padding: var(--space-2) var(--space-4) var(--space-2) 36px;
		font-family: var(--font-family);
		font-size: var(--font-size-base);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text-primary);
		outline: none;
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
	}
	.search-input::placeholder {
		color: var(--color-text-muted);
	}
	.search-input:focus {
		border-color: var(--color-accent);
		box-shadow: 0 0 0 3px var(--color-accent-light);
	}
	.search-clear {
		position: absolute;
		right: var(--space-2);
		top: 50%;
		transform: translateY(-50%);
		background: none;
		border: none;
		cursor: pointer;
		color: var(--color-text-muted);
		padding: var(--space-1);
		border-radius: var(--radius-sm);
		display: flex;
		align-items: center;
		justify-content: center;
		transition: color var(--transition-fast);
	}
	.search-clear:hover {
		color: var(--color-text-primary);
	}

	/* Tags */
	.tag-filters {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		flex-wrap: wrap;
	}
	.tag-label {
		font-size: var(--font-size-sm);
		color: var(--color-text-secondary);
		font-weight: 500;
		white-space: nowrap;
	}
	.tag-list {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
	}
	.tag-chip {
		font-family: var(--font-family);
		font-size: var(--font-size-xs);
		font-weight: 500;
		padding: var(--space-1) var(--space-3);
		border-radius: var(--radius-full);
		border: 1px solid var(--color-border);
		background: var(--color-surface);
		color: var(--color-tag-text);
		cursor: pointer;
		transition: all var(--transition-fast);
		white-space: nowrap;
	}
	.tag-chip:hover {
		border-color: var(--color-accent);
		color: var(--color-accent);
		background: var(--color-accent-light);
	}
	.tag-chip.active {
		background: var(--color-tag-active-bg);
		color: var(--color-tag-active-text);
		border-color: var(--color-tag-active-bg);
	}
	.tag-clear {
		font-family: var(--font-family);
		font-size: var(--font-size-xs);
		font-weight: 500;
		padding: var(--space-1) var(--space-3);
		border-radius: var(--radius-full);
		border: none;
		background: none;
		color: var(--color-accent);
		cursor: pointer;
		transition: opacity var(--transition-fast);
	}
	.tag-clear:hover {
		opacity: 0.7;
	}

	/* Table */
	.table-section {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		box-shadow: var(--shadow-xs);
	}
	.table-wrap {
		overflow-x: auto;
	}
	.table {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--font-size-base);
	}
	.table thead {
		background: var(--color-bg);
	}
	.table th {
		text-align: left;
		padding: var(--space-3) var(--space-4);
		font-size: var(--font-size-xs);
		font-weight: 600;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.04em;
		border-bottom: 1px solid var(--color-border);
		white-space: nowrap;
	}
	.table td {
		padding: var(--space-3) var(--space-4);
		border-bottom: 1px solid var(--color-border-light);
		vertical-align: middle;
	}
	.table-row {
		animation: fadeInRow 300ms ease both;
		transition: background var(--transition-fast);
	}
	.table-row:hover {
		background: var(--color-surface-hover);
	}
	.table-row:last-child td {
		border-bottom: none;
	}

	@keyframes fadeInRow {
		from {
			opacity: 0;
			transform: translateY(4px);
		}
		to {
			opacity: 1;
			transform: translateY(0);
		}
	}

	/* Cells */
	.cell-filename {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		font-weight: 500;
		color: var(--color-text-primary);
		white-space: nowrap;
	}
	.file-icon {
		color: var(--color-accent);
		flex-shrink: 0;
	}
	.cell-date {
		color: var(--color-text-secondary);
		font-size: var(--font-size-sm);
		white-space: nowrap;
	}
	.cell-tags {
		display: flex;
		gap: var(--space-1);
		flex-wrap: wrap;
	}
	.inline-tag {
		display: inline-block;
		font-size: var(--font-size-xs);
		font-weight: 500;
		padding: 2px var(--space-2);
		border-radius: var(--radius-full);
		background: var(--color-tag-bg);
		color: var(--color-tag-text);
		cursor: pointer;
		transition: all var(--transition-fast);
	}
	.inline-tag:hover {
		background: var(--color-accent-light);
		color: var(--color-accent);
	}
	.inline-tag.highlight {
		background: var(--color-tag-active-bg);
		color: var(--color-tag-active-text);
	}
	.cell-words {
		text-align: right;
	}
	.word-count {
		font-variant-numeric: tabular-nums;
		font-weight: 500;
		color: var(--color-text-secondary);
	}

	/* Width hints */
	.th-filename { width: 35%; }
	.th-date { width: 25%; }
	.th-tags { width: 25%; }
	.th-words { width: 15%; text-align: right; }

	/* Empty */
	.empty-state {
		text-align: center;
		padding: var(--space-12) var(--space-6);
	}
	.empty-title {
		font-size: var(--font-size-md);
		font-weight: 600;
		color: var(--color-text-primary);
		margin-top: var(--space-4);
	}
	.empty-subtitle {
		font-size: var(--font-size-sm);
		color: var(--color-text-muted);
		margin-top: var(--space-2);
	}

	/* Responsive */
	@media (max-width: 768px) {
		.header-inner {
			flex-direction: column;
			align-items: flex-start;
			gap: var(--space-4);
		}
		.stats-row {
			width: 100%;
			justify-content: flex-start;
		}
		.search-box {
			max-width: 100%;
		}
		.th-filename { width: auto; }
		.th-date { width: auto; }
		.th-tags { width: auto; }
		.th-words { width: auto; }
	}
</style>
