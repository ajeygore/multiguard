# LLMWiki Agent Instructions

This repository is an **LLMWiki** knowledge base. It is designed to be maintained entirely by LLM agents in collaboration with the user, following the architecture outlined in [Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

---

## Directory Layout

- `/raw/` — Immutable raw source documents (articles, PDFs, logs) that the agent reads but never modifies.
- `/wiki/` — The directory containing all wiki markdown files (concepts, summaries, logs, etc.).
- `/wiki/index.md` — The content catalog containing links and summaries of all pages. Used by the browser engine to construct the navigation sidebar.
- `/wiki/log.md` — The chronological action log.
- `/wiki/skills/` — Custom workspaces-specific skills directory. Each subfolder contains a specialized agent skill.
- `/llmwiki/` — The LLMWiki rendering engine (JS and CSS assets). Never modify files in here.
- `/llmwiki/update.md` — Instruction manual for upgrading the engine to the latest upstream version.
- `/index.html` — The customizable HTML template for human browsing.
- `/agents.md` — This instruction manual.

---

## Operating Guidelines for Agents

When the user asks you to interact with this wiki, you must follow the guidelines for the respective operational flow:

### 1. Ingestion Flow (Adding a Source)
1. **Read and Extract**: Read the raw source provided by the user (usually located under a `/raw/` folder, or provided directly in the prompt). Summarize the key claims and information.
2. **Draft the Summary**: Write a new markdown file in `/wiki/` summarizing the source. Use clear headings, YAML frontmatter tags, and proper citations.
3. **Cross-Reference**:
   - Update existing concept or topic files in `/wiki/` to integrate the new knowledge.
   - Link between files using relative markdown links (e.g., `[Welcome](welcome.md)` or `[Getting Started](getting-started.md)`).
4. **Update Catalog**: Add the new file link and a brief one-line description to `/wiki/index.md`.
5. **Log the Action**: Append an entry to `/wiki/log.md` with the timestamp and action name.

### 2. Query Flow (Answering Questions)
1. **Discover & Search**: Search for relevant terms using the CLI tool `./llmwiki/search "<query>"` or read `/wiki/index.md` to find relevant files.
2. **Synthesize**: Read the matching files and generate an answer citing the relevant pages.
3. **File Back (Compounding)**: If the answer is complex, involves synthesis across multiple files, or presents a useful comparison table, **file it back into the wiki** as a new markdown page (e.g. under a `/wiki/comparisons/` or `/wiki/synthesis/` subdirectory). Link it to `/wiki/index.md` and log the creation.

### 3. Lint Flow (Consistency & Health Check)
Periodically (or when asked), run a lint pass to keep the wiki healthy. Identify and address:
1. **Contradictions**: Discrepancies between older summaries and newer claims. Flag these to the user or reconcile them.
2. **Stale Claims**: Superseded facts that are no longer accurate based on newer documents.
3. **Orphan Pages**: Pages in `/wiki/` that have no inbound links from the rest of the wiki (or are missing from `wiki/index.md`).
4. **Data Gaps & Missing Links**: Concepts mentioned on pages that would benefit from having their own page or linking to an existing page.

---

## 🛠️ Workspace Custom Skills (`/wiki/skills/`)

Custom coding agent capabilities can be packaged as skills inside `/wiki/skills/<skill_name>/`. Visiting agents must load and follow these skills:
- **`SKILL.md`**: Main manifest defining frontmatter `name` and `description` + instruction rules.
- **`references/`**: Place API manuals, library specs, or database schemas in this folder. Keep files short and split to remain token-efficient.
- **`scripts/`**: Helper scripts the agent can run.

### 🔄 Loops & Scheduling Policies
If executing automated loops or scheduled agent flows (cron triggers, cron iteration timer schedules):
- **Safety Terminations**: All agent execution loops MUST declare a clean early-termination condition (e.g., "stop when `/raw/` is empty" or a maximum limit of 5 consecutive iterations).
- **Scheduled Runs**: Automations running on system schedules (like hourly indexing or daily lint runs) must document their cron schedules in `wiki/skills/` and log execution metrics to `/wiki/log.md`.

---

## File and Link Conventions
- Maintain a clean hierarchy.
- Use relative links without folders if the file is in the same directory (e.g., `[Welcome](welcome.md)`).
- Prefix pages with YAML frontmatter containing `title`, `tags`, and `summary` tags:
  ```yaml
  ---
  title: Page Title
  tags: [tag1, tag2]
  summary: Brief one-sentence summary.
  ---
  ```
- **Never** break the structure of `/wiki/index.md` as it is parsed by the client-side viewer.

---

## Log Formatting
All logs in `/wiki/log.md` must use the parseable prefix format:
`## [YYYY-MM-DD] action | Description`
This makes the logs parseable via unix command-line tools.

---

## Reprocess After Every Major Task

A wiki is only worth reading if it is current. **After every major task in the
project this wiki documents, reprocess the wiki, commit, and push.**

**Major** means: a merged change that alters behaviour, a completed piece of
work, a decision, a deploy, or an incident whose diagnosis is worth keeping.
Not: typo fixes, dependency bumps, or refactors that change nothing observable.

1. **Log it** — append to `/wiki/log.md` in the parseable format above.
2. **Update the pages the change made wrong.** A change that invalidates a page
   is not finished until the page is right.
3. **Record the decision**, if a real choice was made — including the options
   rejected and why. That is what nobody can reconstruct later.
4. **Update any verbatim copies under `/raw/`** if their sources changed.
   Snapshots rot silently.
5. **Catalog it** — every new page must be linked from `/wiki/index.md`, or it
   is an orphan nobody will find.
6. **Lint, then commit.** Run `./llmwiki/lint` **after your last edit**,
   including the log entry itself, and fix what it reports:
   ```bash
   ./llmwiki/lint && git add -A && git commit && git push
   ```
7. **Push.** An updated wiki nobody else can see has not been updated.

Nothing fails when a wiki goes stale — it simply misleads the next person, and
it does so with the authority of written documentation. That is why this is a
step in the work rather than an afterthought.

**Never put secret values in a wiki.** Referencing where a secret lives is
fine; the value never is. A private repository is not the same as a safe place
for a credential.
