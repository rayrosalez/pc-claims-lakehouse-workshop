# Databricks notebook source
# MAGIC %md
# MAGIC # Lab 00 — Setup: schemas, landing volume, synthetic P&C data
# MAGIC
# MAGIC Run this notebook **top to bottom** on serverless compute. It takes about a minute.
# MAGIC
# MAGIC It creates:
# MAGIC
# MAGIC | Object | What it is |
# MAGIC |---|---|
# MAGIC | `lab_landing` schema | The "source systems": a landing **volume** for claim files plus `policies` and `properties` extracts |
# MAGIC | `lab_bronze`, `lab_silver`, `lab_gold` | Medallion layers for the **dev** target |
# MAGIC | `lab_prod_bronze`, `lab_prod_silver`, `lab_prod_gold` | Medallion layers for the simulated **prod** target |
# MAGIC | `/Volumes/<catalog>/lab_landing/raw/claims/batch_01.json` | First claim batch (clean) |
# MAGIC | `/Volumes/<catalog>/lab_landing/raw/staging/` | `batch_02` (bad rows + claim updates) and `batch_03` (new column), landed later by lab 02 |
# MAGIC
# MAGIC All data is synthetic and generated here; nothing is downloaded (Free Edition restricts outbound internet).

# COMMAND ----------

dbutils.widgets.text("catalog", "workspace", "Catalog")
dbutils.widgets.dropdown("reset", "false", ["false", "true"], "Reset landing files")

catalog = dbutils.widgets.get("catalog")
reset = dbutils.widgets.get("reset") == "true"

SCHEMAS = ["lab_landing", "lab_bronze", "lab_silver", "lab_gold",
           "lab_prod_bronze", "lab_prod_silver", "lab_prod_gold"]

spark.sql(f"USE CATALOG `{catalog}`")
for s in SCHEMAS:
    spark.sql(f"CREATE SCHEMA IF NOT EXISTS `{catalog}`.{s}")

spark.sql(f"CREATE VOLUME IF NOT EXISTS `{catalog}`.lab_landing.raw "
          "COMMENT 'Landing zone for raw files from the claims system.'")

RAW = f"/Volumes/{catalog}/lab_landing/raw"
CLAIMS_DIR = f"{RAW}/claims"
STAGING_DIR = f"{RAW}/staging"

if reset:
    dbutils.fs.rm(CLAIMS_DIR, recurse=True)
    dbutils.fs.rm(STAGING_DIR, recurse=True)
dbutils.fs.mkdirs(CLAIMS_DIR)
dbutils.fs.mkdirs(STAGING_DIR)
print(f"Schemas and volume ready in catalog '{catalog}'")

# COMMAND ----------

# MAGIC %md ## Generate policies, properties, and three claim batches

# COMMAND ----------

import datetime as dt
import json
import random

random.seed(42)
TODAY = dt.date.today()
NOW = dt.datetime.now().replace(microsecond=0)

STATES = ["CA", "TX", "FL", "NY", "IL", "PA", "CT", "OH", "GA", "NC", "NJ", "MA", "MN", "AZ", "WA"]
STATE_W = [14, 12, 11, 9, 6, 6, 6, 5, 5, 5, 5, 5, 4, 4, 3]

# line of business -> (share of policies, target loss ratio, causes of loss, severity mu/sigma, segments)
LOBS = {
    "Personal Auto":        (0.32, 0.68,     ["Collision", "Comprehensive", "Bodily Injury", "Glass", "Theft"], (8.2, 0.9), ["Personal"]),
    "Homeowners":           (0.26, 0.58,    ["Wind/Hail", "Water Damage", "Fire", "Theft", "Liability"],        (8.6, 1.0), ["Personal"]),
    "Commercial Property":  (0.14, 0.52,   ["Wind/Hail", "Fire", "Water Damage", "Equipment Breakdown"],      (10.0, 1.1), ["Small Commercial", "Middle Market"]),
    "Workers Compensation": (0.14, 0.62,   ["Strain", "Slip and Fall", "Struck By Object", "Cut/Laceration"], (8.8, 1.0), ["Small Commercial", "Middle Market"]),
    "General Liability":    (0.14, 0.55,   ["Slip and Fall", "Products Liability", "Property Damage to Others"], (9.3, 1.2), ["Small Commercial", "Middle Market"]),
}
FIRST = ["Alex", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Jamie", "Avery", "Quinn", "Drew", "Sam", "Robin"]
LAST = ["Smith", "Garcia", "Chen", "Patel", "Johnson", "Nguyen", "Brown", "Lopez", "Kim", "Miller", "Davis", "Wilson"]
BIZ = ["Holdings", "Logistics", "Builders", "Foods", "Partners", "Manufacturing", "Dental", "Hospitality"]

def rand_date(start, end):
    return start + dt.timedelta(days=random.randint(0, max(0, (end - start).days)))

# --- policies ------------------------------------------------------------
policies = []
lob_names = list(LOBS)
lob_weights = [LOBS[l][0] for l in lob_names]
for i in range(1, 20001):
    lob = random.choices(lob_names, lob_weights)[0]
    segs = LOBS[lob][4]
    seg = random.choice(segs)
    eff = rand_date(TODAY - dt.timedelta(days=3 * 365), TODAY - dt.timedelta(days=30))
    name = (f"{random.choice(FIRST)} {random.choice(LAST)}" if seg == "Personal"
            else f"{random.choice(LAST)} {random.choice(BIZ)} LLC")
    policies.append({
        "policy_id": f"P{i:06d}",
        "line_of_business": lob,
        "state": random.choices(STATES, STATE_W)[0],
        "effective_date": eff,
        "expiration_date": eff + dt.timedelta(days=365),
        "written_premium": None,          # priced below, once claims exist
        "customer_segment": seg,
        "agency_id": f"A{random.randint(1, 60):03d}",
        "insured_name": name,
    })

properties = []
for p in policies:
    if p["line_of_business"] in ("Homeowners", "Commercial Property"):
        properties.append({
            "property_id": f"R{len(properties) + 1:06d}",
            "policy_id": p["policy_id"],
            "state": p["state"],
            "construction_type": random.choice(["Frame", "Masonry", "Joisted Masonry", "Fire Resistive"]),
            "year_built": random.randint(1950, 2024),
            "total_insured_value": round(random.uniform(250_000, 900_000) if p["line_of_business"] == "Homeowners"
                                         else random.uniform(1_000_000, 25_000_000), 2),
            "coastal": p["state"] in ("FL", "TX", "NC", "GA", "NJ", "MA", "CT", "NY", "CA"),
        })

# --- claims ----------------------------------------------------------------
claim_seq = 0

def new_claim(policy, loss_start=None, cause=None, cat_event_code=None):
    global claim_seq
    claim_seq += 1
    _, _, causes, (mu, sigma), _ = LOBS[policy["line_of_business"]]
    lo = max(policy["effective_date"], loss_start or policy["effective_date"])
    hi = min(policy["expiration_date"], TODAY - dt.timedelta(days=3))
    loss = rand_date(lo, hi)
    report = min(loss + dt.timedelta(days=random.choice([0, 0, 1, 2, 3, 5, 9, 14, 30])), TODAY - dt.timedelta(days=2))
    severity = round(min(random.lognormvariate(mu, sigma), 750_000.0), 2)
    age = (TODAY - loss).days
    closed = random.random() < min(0.9, age / 400)
    paid = severity if closed else round(severity * random.uniform(0.0, 0.5), 2)
    claim = {
        "claim_id": f"C{claim_seq:07d}",
        "policy_id": policy["policy_id"],
        "line_of_business": policy["line_of_business"],
        "state": policy["state"],
        "loss_date": loss.isoformat(),
        "report_date": report.isoformat(),
        "cause_of_loss": cause or random.choice(causes),
        "claim_status": "CLOSED" if closed else "OPEN",
        "paid_amount": float(paid),
        "reserve_amount": 0.0 if closed else float(round(severity - paid, 2)),
        "adjuster_id": f"ADJ{random.randint(1, 120):04d}",
        "updated_at": dt.datetime.combine(min(report + dt.timedelta(days=random.randint(0, 60)),
                                              TODAY - dt.timedelta(days=1)),
                                          dt.time(random.randint(8, 18), random.randint(0, 59))).isoformat(),
    }
    if cat_event_code is not None or cause is not None:
        claim["cat_event_code"] = cat_event_code
    return claim

eligible = [p for p in policies if p["effective_date"] < TODAY - dt.timedelta(days=5)]

# batch_01: clean
batch_01 = [new_claim(random.choice(eligible)) for _ in range(6000)]

# Price policies so loss ratios land in a realistic band: premium ~ expected loss / target loss ratio,
# with a per-state rate level and per-policy noise.
state_rate = {st: random.uniform(0.85, 1.2) for st in STATES}
for lob in LOBS:
    lob_policies = [p for p in policies if p["line_of_business"] == lob]
    incurred = sum(c["paid_amount"] + c["reserve_amount"] for c in batch_01 if c["line_of_business"] == lob)
    expected_loss = incurred / len(lob_policies)
    for p in lob_policies:
        p["written_premium"] = round(max(300.0, expected_loss / LOBS[lob][1]
                                         * state_rate[p["state"]] * random.lognormvariate(0, 0.3)), 2)

# batch_02: new claims + updates to open claims + bad rows
batch_02 = [new_claim(random.choice(eligible)) for _ in range(1200)]
open_claims = [c for c in batch_01 if c["claim_status"] == "OPEN"]
for c in random.sample(open_claims, min(400, len(open_claims))):
    batch_02.append({**c,
                     "claim_status": "CLOSED",
                     "paid_amount": float(round(c["paid_amount"] + c["reserve_amount"], 2)),
                     "reserve_amount": 0.0,
                     "updated_at": NOW.isoformat()})
for _ in range(30):                      # missing policy -> dropped by valid_policy_id
    batch_02.append({**new_claim(random.choice(eligible)), "policy_id": None})
for _ in range(20):                      # negative paid -> dropped by non_negative_paid
    c = new_claim(random.choice(eligible))
    batch_02.append({**c, "paid_amount": -abs(c["paid_amount"]) - 100.0})
random.shuffle(batch_02)

# batch_03: recent claims, some tied to a catastrophe event (new column cat_event_code)
cat_code = f"CAT-{TODAY:%Y-%m}-WIND"
cat_policies = [p for p in eligible
                if p["line_of_business"] in ("Homeowners", "Commercial Property")
                and p["state"] in ("FL", "TX", "NC", "GA")
                and p["expiration_date"] > TODAY - dt.timedelta(days=20)]
batch_03 = []
for _ in range(800):
    if random.random() < 0.45 and cat_policies:
        batch_03.append(new_claim(random.choice(cat_policies), loss_start=TODAY - dt.timedelta(days=20),
                                  cause="Wind/Hail", cat_event_code=cat_code))
    else:
        p = random.choice([p for p in eligible if p["expiration_date"] > TODAY - dt.timedelta(days=45)])
        c = new_claim(p, loss_start=TODAY - dt.timedelta(days=45))
        c["cat_event_code"] = None
        batch_03.append(c)

print(f"policies={len(policies)} properties={len(properties)} "
      f"batch_01={len(batch_01)} batch_02={len(batch_02)} batch_03={len(batch_03)}")

# COMMAND ----------

# MAGIC %md ## Write the source-system extracts and claim files

# COMMAND ----------

from pyspark.sql.types import (StructType, StructField, StringType, DateType, DoubleType,
                               IntegerType, BooleanType)

policy_schema = StructType([
    StructField("policy_id", StringType()), StructField("line_of_business", StringType()),
    StructField("state", StringType()), StructField("effective_date", DateType()),
    StructField("expiration_date", DateType()), StructField("written_premium", DoubleType()),
    StructField("customer_segment", StringType()), StructField("agency_id", StringType()),
    StructField("insured_name", StringType()),
])
property_schema = StructType([
    StructField("property_id", StringType()), StructField("policy_id", StringType()),
    StructField("state", StringType()), StructField("construction_type", StringType()),
    StructField("year_built", IntegerType()), StructField("total_insured_value", DoubleType()),
    StructField("coastal", BooleanType()),
])

(spark.createDataFrame(policies, policy_schema)
      .write.mode("overwrite").option("overwriteSchema", "true")
      .saveAsTable(f"`{catalog}`.lab_landing.policies"))
(spark.createDataFrame(properties, property_schema)
      .write.mode("overwrite").option("overwriteSchema", "true")
      .saveAsTable(f"`{catalog}`.lab_landing.properties"))

def write_jsonl(path, rows):
    with open(path, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")

write_jsonl(f"{STAGING_DIR}/batch_01.json", batch_01)
write_jsonl(f"{STAGING_DIR}/batch_02.json", batch_02)
write_jsonl(f"{STAGING_DIR}/batch_03.json", batch_03)
dbutils.fs.cp(f"{STAGING_DIR}/batch_01.json", f"{CLAIMS_DIR}/batch_01.json")

display(dbutils.fs.ls(CLAIMS_DIR))

# COMMAND ----------

# MAGIC %md
# MAGIC ## Done
# MAGIC
# MAGIC `batch_01.json` is in the landing folder. The pipeline (lab 3) will pick it up.
# MAGIC Next: **`labs/01_uc_medallion.sql`**.
