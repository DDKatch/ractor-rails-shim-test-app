# DOCSTYLE — ractor-rails-shim-test-app

## Structure
- When updating a benchmark table with new data, keep every existing row and add a `Run` (date) column instead of deleting rows. Different run dates may share a table but must be labeled per row.
- Bold = best value within comparable rows (same run date). Never bold across different run dates.

## Terminology
- GET endpoints in table headers carry the `GET` prefix (`GET /posts_plain (rps)`), consistent with `GET /posts` and `POST /posts`. Prose references stay as plain endpoint names.
