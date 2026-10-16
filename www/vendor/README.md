# Vendored third-party scripts (all loaded locally, never from a CDN)

- `pdf.min.js` — pdf.js **3.11.174** UMD build, downloaded from
  https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.min.js
- `pdf.worker.min.js` — pdf.js **3.11.174** worker, downloaded from
  https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.worker.min.js
  License: Apache-2.0 (Mozilla Foundation). Used for on-device bank-statement
  PDF text extraction in the Import/export dialog (the main script auto-falls
  back to this worker file; it is also set explicitly in app.js).
  No network access is used or required — both files are served from app
  assets via MainActivity's asset allowlist.
