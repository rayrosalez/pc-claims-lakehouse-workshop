# Lab 04 — Ask questions of your gold layer in Genie

## Create the Genie space

1. Left nav → **Genie** → **New**.
2. Add these tables from `workspace.lab_gold`:
   - `claims_detail`
   - `claims_loss_summary`
   - `loss_ratio_by_lob_state`
3. Title: `Claims Loss Analytics`. Warehouse: **Serverless Starter Warehouse**.
4. Open the space from **Databricks One** (app switcher, top right → **Databricks One**) to see it the way a business user would.

## Ask these three questions

| # | Question | What to look for |
|---|---|---|
| 1 | *Which states had the highest paid losses last quarter?* | Open **Show code**. Genie used `claims_loss_summary.paid_losses` and filtered `loss_month`. It found those columns because of the comments you saw in the pipeline SQL. |
| 2 | *Break that down by line of business.* (follow-up) | Genie keeps the context from question 1. |
| 3 | *What's our loss ratio?* | **Deliberately ambiguous.** Overall or by line? Earned or written premium? Calendar or policy year? Compare what Genie assumes with what you meant. |

## Fix the ambiguous one

Ambiguity is fixed with **context**, not a bigger model. Pick one:

- **Instructions** (space → Configure → Instructions):
  `"Loss ratio" means incurred_losses / written_premium from loss_ratio_by_lob_state. Report it as a percentage. If no line of business is given, return all lines plus a total weighted by written_premium.`
- **Example SQL** (space → Configure → SQL queries): save a query for "overall loss ratio" so Genie reuses it.

Ask question 3 again and compare the answers.

## More to try

- *How many claims were caused by Wind/Hail in Florida in the last 30 days?*
- *What is the average report lag by line of business?*
- *Which agencies have the most open claims?*
- *Show monthly incurred losses for Homeowners over the last 12 months as a line chart.*
- *Who is the insured on policy P000123?* (Genie can't answer: `insured_name` never reaches gold. That's governance by design.)
