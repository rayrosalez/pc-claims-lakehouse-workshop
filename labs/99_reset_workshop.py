# Databricks notebook source
# MAGIC %md
# MAGIC # Reset the workshop
# MAGIC
# MAGIC Drops every `lab_*` schema (tables, volume, and files). Destroy the bundle first
# MAGIC (Deployments pane → **Destroy**, or `databricks bundle destroy -t dev`) so the
# MAGIC pipeline doesn't try to write to schemas that no longer exist.
# MAGIC Then re-run `00_setup_generate_data` to start over.

# COMMAND ----------

dbutils.widgets.text("catalog", "workspace", "Catalog")
dbutils.widgets.dropdown("confirm", "no", ["no", "yes"], "Really drop everything?")

catalog = dbutils.widgets.get("catalog")
if dbutils.widgets.get("confirm") != "yes":
    dbutils.notebook.exit("Set confirm = yes to drop the lab schemas.")

for s in ["lab_landing", "lab_bronze", "lab_silver", "lab_gold",
          "lab_prod_bronze", "lab_prod_silver", "lab_prod_gold"]:
    spark.sql(f"DROP SCHEMA IF EXISTS `{catalog}`.{s} CASCADE")
    print("dropped", s)
