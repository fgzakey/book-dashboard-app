# Book Dashboard — Android app (phone + tablet)

Flutter companion app for the [Book Dashboard](https://huggingface.co/spaces/fgza/book-dashboard) — a co-reading cognitive tool for books. It is a thin client of the same backend (the Hugging Face Space), so it reads and writes the **same Neon Postgres database** as the web version: books, chats, prompts, results, image catalogs, and whiteboards all sync both ways.

## Features (full web parity)

- **Books** — upload epubs from the device, browse the shared library, read chapters and full text, delete.
- **Chat (Ask questions)** — streaming answers about any book, same system prompt as the web; history syncs.
- **Prompts & Wisdom** — built-in + custom standardized prompts, run against the whole book or selected chapters, live streaming output, save to Results.
- **Results** — searchable saved-results library with Markdown rendering.
- **Images & Figures** — every image in the epub grouped by chapter, AI describe (vision model titles, transcribes and explains each image), AI upscale, Markdown catalog, server-built PDF report (shareable).
- **Visual Scribe** — whiteboard / memory palace / knowledge-graph boards with AI-painted illustrations in 7 art styles; boards render as the same SVG as the web (shared record shape) and can be shared as SVG or graph JSON.
- **Settings** — server URL, app password, optional OpenRouter key, model picker, temperature.

No database credentials live in the app. It calls the dashboard's API routes (`/api/epub`, `/api/chat`, `/api/db/*`, `/api/models`, `/api/images/*`, `/api/scribe`, `/api/upscale`, `/api/prompts/defaults`) and authenticates with the same `APP_PASSWORD` as the web login (sent as the `book_auth` cookie).

## Building the APK (GitHub Actions — no local toolchain needed)

Push to `main` and the **Build Android APK** workflow builds a release APK and publishes it:

- repo **Releases → "Latest APK"** (rolling), or
- the workflow run's **Artifacts**.

On the phone, download the APK from Releases, open it, and allow "install from this source". Because CI builds are debug-key signed, **uninstall the previous version before installing an updated APK**.

## First-run setup in the app

1. Server URL: the Space's **direct** URL, e.g. `https://fgza-book-dashboard.hf.space` (not the huggingface.co page).
2. App password: the same `APP_PASSWORD` as the web login.
3. OpenRouter key: only if the Space has no `OPENROUTER_API_KEY` secret.
4. Tap **Save & test connection**, then pick a model.

## Local development

```
flutter pub get
flutter run
```
