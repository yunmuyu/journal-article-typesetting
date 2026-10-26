# Discontinuous article checks and PDF render gate

For an article that resumes after intervening articles, supply `articlePageIndices`
as a nonempty, strictly increasing array of zero-based physical document offsets.
It is mutually exclusive with the existing continuous `articlePageRange`.
The view retains actual document offsets and requires all bound story frames to
be within the declared scope. This prevents omitted continuation frames from
silently passing. Apply remains forbidden for either full-document scope mode.

The page set applies to page/item/graphic audit views, native preflight partitioning
and Check previews. A truly blank declared page remains an error. Ambiguous native
preflight locations remain blocking. Objects of another article on a shared page
are not automatically attributed to an article by this change.

PDF export now requires `-PdfRenderValidator` (or `JOURNAL_PDF_RENDER_VALIDATOR`)
pointing to the `journal-ai-production` source module
`portable-production/localflow/pdf_render.py`. Supply a Python environment with
that project's existing PyMuPDF dependency. No renderer code is copied into this
repository. The caller should pin both repositories and verify their hashes.
The validator runs in isolation and must report a complete, error-free render
before the temporary export becomes the delivered PDF. Missing validator fails
before Adobe export. `-PlanOnly` remains a non-executing plan.

Validation: new scope regression failed before the fix and passes after it.
The existing preflight-scope, integrated-article, preview-range and empty-region
regressions pass. A native QA replay removed three false empty-page errors while
retaining other failures; this is not full article acceptance. A separate native
two-page synthetic export passed the shared render gate and a Poppler render was
visually inspected. No production document is needed by the new tests.

The broader CJS run is 74 passed / 1 failed: the existing Python autodiscovery
test also fails against the unchanged handoff snapshot on this host. It clears
the explicit interpreter override and cannot find a supported Python executable.
That environment-dependent test is not suppressed or counted as passing.

Run from the repository root:

```powershell
node tests/run_discontinuous_article_scope_regression.cjs
node tests/run_article_preflight_scope_regression.cjs
node tests/run_preview_pdf_range_regression.cjs
tests/run_pdf_render_validation_regression.ps1 -PythonExe <python> -ValidatorPath <pdf_render.py> -ValidPdf <synthetic-valid.pdf> -InvalidPdf <synthetic-corrupt.pdf>
```

Render success checks decodability; it does not approve layout, manuscript content,
fonts' appearance, print quality, or editorial decisions.
