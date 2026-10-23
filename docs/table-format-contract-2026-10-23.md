# Table format classification and static regression contract

This change keeps source evidence separate from a reviewed table kind. Extraction
records the explicit Word table style ID and explicit table/cell borders in
`table-structure.json`. Missing border attributes remain missing; they do not
mean zero-width borders. No author text or article-specific mapping is stored
in the repository.

For a new table assembly job, pass `--table-kinds PATH` to
`prepare_article_job.py`. The UTF-8 JSON maps one-based table numbers to a
reviewed kind and a short reason, for example:

```json
{
  "1": {"kind": "ordinary", "reviewEvidence": "Verified full-grid data table"},
  "2": {"kind": "algorithm", "reviewEvidence": "Verified algorithm heading and left-aligned steps"}
}
```

Supported kind labels are `ordinary`, `three-line`, and `algorithm`. Omitted
numbers are `unclassified`. The job and audit config carry both this decision
and the extracted source evidence. The generic assembly currently builds only
reviewed `ordinary` tables; it rejects the other kinds before changing the
article. Existing algorithm or three-line tables retain their native cell
format during ordinary-table normalization. A Check with an unclassified table
reports `TABLE_KIND_REQUIRED` instead of assuming an ordinary data table.

For ordinary tables, `JournalLayout` restores four 0.5 mm insets, four 0.5 pt
strokes, vertical centering and auto growth. It preserves a valid 4.6–5.5 mm
minimum row height and repairs only missing or out-of-range values to 5 mm;
actual multiline height grows naturally. Horizontal centering is the default
for unprotected cells. Existing right alignment and tabbed cells are preserved,
and numeric decimal columns are not recentered.

The native audit measures decimal-point X coordinates within 0.1 mm in each
numeric decimal column. A right-aligned paragraph or tab alone is not proof
of alignment; unavailable geometry fails measurement. New assembly blocks a
variable-shape decimal column before document acquisition with
`TABLE_DECIMAL_ALIGNMENT_REVIEW_REQUIRED`, because the importer has no verified
native alignment plan for it. Numeric-shape detection reuses the read-only
logic of the user's checker; its UI, selection changes and toggle formatting
are excluded.

The snapshot stores actual row height, minimum height, auto growth, and table
kind. Comparison checks cell native format and row constraints. It accepts
column-width redistributions preserving the total width and actual height
changes subject to the quality gate; invalid columns and changed total width
fail. For newly created ordinary tables without explicit widths, bounded
candidate search uses the recomposed sum of actual row heights as its score.
The extracted Word proportions seed the search but are not the objective.
Search is bounded to 300 measurements and is not a proof of global optimum.

Static validation on the branch: 74 CJS and three other JavaScript entry
points passed after excluding the two known main failures fixed separately
in PR #2; Python unittest discovery passed 47 tests.
Those checks use synthetic samples. The historical IDML evidence for the three
reported tables predates the user's changed 19th-issue PDF, so it does not
identify current PDF attributes. No InDesign or Illustrator process was run.
Native E2E and visual review must be scheduled by the production controller.
