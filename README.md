# P&C Claims Lakehouse Workshop

A 90-minute hands-on build on **Databricks Free Edition**. One repo, one dataset, one story:

```
code (Git)  →  organize (Unity Catalog)  →  promote (pipeline + bundle)  →  harden (Delta)  →  consume (Genie)
```

You'll land synthetic property & casualty claims in **bronze**, promote them through **silver** and
**gold** with a bundle-deployed declarative pipeline, harden a published gold table (liquid clustering,
UniForm, constraints, time travel), and then ask questions about your own gold tables in **Genie**.

All data is synthetic and generated inside your workspace.

---

## Pre-work (do this before the session, about 5 minutes)

1. Sign up for **Databricks Free Edition** at <https://www.databricks.com/learn/free-edition> with a personal email.
2. Complete the email one-time-passcode login once.
3. Open **Workspace → Create → Notebook** and run `SELECT 1`. If you see a result, you're ready.

If your network blocks the sign-up or the OTP email, tell the instructor before the session.

---

## Lab steps

### Segment 1: clone the repo (5 min)

1. **Workspace → your home folder → Create → Git folder.**
2. Git repository URL: `https://github.com/rayrosalez/pc-claims-lakehouse-workshop` (public, no credentials needed). Click **Create Git folder**.
3. *Optional:* the clone is read-only on GitHub (you can edit files in your workspace, but you can't push to this repo).
   To practice the full branch → commit → push → PR flow, **fork** the repo to your own GitHub account first, clone your fork,
   and add a GitHub personal access token under **Settings → Linked accounts**. Then click the branch name → **Create branch** → `dev-<yourname>`.
4. Open `labs/00_setup_generate_data` and click **Run all** (serverless). It takes about a minute. Move on while it runs.

### Segment 2: Unity Catalog + medallion design (8 min)

Open `labs/01_uc_medallion` and work top to bottom. Fill in the two `____` blanks.

- Query raw files in the volume with `read_files()` (schema-on-read)
- Add comments and a `data_classification` tag to `lab_landing.policies`
- `GRANT` read access on the gold schema, then `SHOW GRANTS`
- Find the volume, the table, its tags, and its permissions in **Catalog Explorer**

### Segment 3: promote with the pipeline + bundle (12 min)

1. Open `databricks.yml` in your Git folder. Click the **Deployments** (rocket) icon in the left pane.
2. Target `dev` → **Deploy**. This creates the `[dev <you>] pc_claims_pipeline` pipeline and the `pc_claims_refresh` job.
3. In the Deployments pane, run **`pc_claims_refresh`**. Open the pipeline to watch bronze → silver → gold build.
4. Run `labs/02_land_more_data` with `batch = batch_02`, then run the job again.
5. In the pipeline, click `claims_validated` and look at the **data quality** metrics: 50 rows dropped at the silver gate, while gold stays clean.
6. **Stretch:** [`solutions/stretch_fail_update.md`](solutions/stretch_fail_update.md)

> Stick to the `dev` target in the lab. `prod` is simulated with `lab_prod_*` schemas; in a real setup it's a
> separate workspace or catalog, deployed only by CI as a service principal.

### Segment 4: liquid clustering, UniForm, time travel, contracts (10 min)

Open `labs/03_delta_uniform_lc`. Fill in the two `____` blanks and **run cells one at a time**: one INSERT
is supposed to fail (that's the constraint doing its job), and **Run all** would stop there.

1. Create a gold snapshot table with liquid clustering and UniForm (Iceberg reads)
2. Add a `CHECK (paid_amount >= 0)` constraint and watch a bad insert fail
3. Land `batch_03` (new column `cat_event_code`), re-run the job, merge into the snapshot, then use `DESCRIBE HISTORY`, `VERSION AS OF`, and `RESTORE`
4. **Stretch:** [`solutions/stretch_contract_change.md`](solutions/stretch_contract_change.md)

### Segment 5: Genie (5 min)

Follow [`labs/04_genie_questions.md`](labs/04_genie_questions.md).

---

## Repo layout

```
├── databricks.yml                 # bundle: variables + dev/prod targets
├── resources/
│   ├── claims_pipeline.yml        # serverless declarative pipeline (bronze → silver → gold)
│   └── claims_job.yml             # job: refresh pipeline → validate gold
├── src/
│   ├── pipeline/
│   │   ├── 01_bronze_claims.sql   # streaming table via Auto Loader (read_files)
│   │   ├── 02_silver_claims.sql   # typed + expectations + AUTO CDC dedup; policies
│   │   └── 03_gold_claims.sql     # MVs: claim detail, loss summary, loss ratio
│   └── validate_gold.sql          # post-refresh data checks (job task)
├── labs/
│   ├── 00_setup_generate_data.py  # schemas, landing volume, synthetic data, batch_01
│   ├── 01_uc_medallion.sql        # read_files, comments, tags, grants
│   ├── 02_land_more_data.py       # lands batch_02 (bad rows + updates) / batch_03 (new column)
│   ├── 03_delta_uniform_lc.sql    # clustering, UniForm, constraints, history, time travel, restore
│   ├── 04_genie_questions.md      # Genie space + starter questions
│   └── 99_reset_workshop.py       # drop everything and start over
├── solutions/                     # completed labs + stretch exercises
└── .github/workflows/deploy.yml   # reference CI: validate on PR, deploy prod on merge
```

### What gets created

| Schema | Contents |
|---|---|
| `lab_landing` | `raw` volume (claim JSON files), `policies`, `properties` (source-system extracts) |
| `lab_bronze` | `claims_raw` |
| `lab_silver` | `claims_validated`, `claims` (one row per claim), `policies` |
| `lab_gold` | `claims_detail`, `claims_loss_summary`, `loss_ratio_by_lob_state`, `claims_snapshot` (lab 03) |
| `lab_prod_*` | Same tables, written by the `prod` target |

The catalog is a bundle variable and a notebook widget, defaulting to `workspace` (Free Edition's catalog).
To use a different catalog, change `catalog` in both places.

---

## Try it later: develop from your IDE

The same repo works from VS Code or Cursor:

```bash
git clone https://github.com/rayrosalez/pc-claims-lakehouse-workshop && cd pc-claims-lakehouse-workshop
databricks auth login --host https://<your-free-edition-host>   # opens a browser for OAuth
databricks bundle validate
databricks bundle deploy -t dev
databricks bundle run claims_job -t dev
```

Install the **Databricks extension** for VS Code to run files and notebook cells on serverless through
Databricks Connect. Recommended flow: edit and test locally → push a branch → PR review → CI deploys the bundle.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Git folder clone fails | Your network may block GitHub from the workspace. Download the repo ZIP from GitHub and use **Workspace → Import**. |
| `SCHEMA_NOT_FOUND` when the pipeline runs | Run `labs/00_setup_generate_data` first. It creates the schemas. |
| Warehouse lookup fails on deploy | The bundle looks for a warehouse named **Serverless Starter Warehouse**. If yours has a different name, change `warehouse_id.lookup.warehouse` in `databricks.yml`. |
| Pipeline queued or hits a compute limit | Free Edition has daily compute quotas. Stop pipelines or jobs you aren't using, and don't run both targets. |
| `batch_02` dropped nothing | The bad rows were already processed in an earlier run. Use **Full refresh all** on the pipeline. |
| Fell behind | Every lab has a completed version in `solutions/`. |
| Want a clean slate | Destroy the bundle, run `labs/99_reset_workshop` (confirm = yes), then re-run `00_setup`. |
