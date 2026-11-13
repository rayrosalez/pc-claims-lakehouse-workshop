# Databricks notebook source
# MAGIC %md
# MAGIC # Lab 02 — Land another claim batch
# MAGIC
# MAGIC Simulates the claims system dropping a new file into the landing volume.
# MAGIC
# MAGIC | Batch | What's in it | Used in |
# MAGIC |---|---|---|
# MAGIC | `batch_02` | 1,200 new claims, 400 **updates** to open claims (now closed), 30 rows with **null `policy_id`**, 20 rows with **negative `paid_amount`** | Segment 3: expectations at the silver gate |
# MAGIC | `batch_03` | 800 recent claims with a **new column `cat_event_code`** (catastrophe event) | Segment 4: schema evolution + data contracts |
# MAGIC
# MAGIC Pick the batch in the widget at the top, run the notebook, then re-run the pipeline.

# COMMAND ----------

dbutils.widgets.text("catalog", "workspace", "Catalog")
dbutils.widgets.dropdown("batch", "batch_02", ["batch_02", "batch_03"], "Batch to land")

catalog = dbutils.widgets.get("catalog")
batch = dbutils.widgets.get("batch")

RAW = f"/Volumes/{catalog}/lab_landing/raw"
dbutils.fs.cp(f"{RAW}/staging/{batch}.json", f"{RAW}/claims/{batch}.json")
print(f"Landed {batch}.json")
display(dbutils.fs.ls(f"{RAW}/claims"))

# COMMAND ----------

# MAGIC %md
# MAGIC ### Peek at what just landed
# MAGIC Schema-on-read: `read_files` infers the columns straight from the file.

# COMMAND ----------

df = spark.read.json(f"{RAW}/claims/{batch}.json")
if batch == "batch_02":
    display(df.selectExpr(
        "count(*) AS rows",
        "count_if(policy_id IS NULL) AS null_policy_id",
        "count_if(paid_amount < 0) AS negative_paid",
    ))
else:
    display(df.groupBy("cat_event_code").count())

# COMMAND ----------

# MAGIC %md
# MAGIC ### Next
# MAGIC Re-run the **pc_claims_refresh** job (or the pipeline) and open the pipeline's **data quality** view.
