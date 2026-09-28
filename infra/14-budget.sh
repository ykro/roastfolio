#!/usr/bin/env bash
# Monthly budget with email alerts. A budget only ALERTS: the hard stop is the app's daily cap
# (DAILY_ROAST_LIMIT in web, 450 roasts ~ $28/day of AI). 900 USD = 30 days x ~30 USD.
# The billing account id is read at run time so it never lands in the repo.
source "$(dirname "$0")/env.sh"
BUDGET_NAME="roastfolio - 30 USD diarios"
BUDGET_AMOUNT="${BUDGET_AMOUNT:-900USD}"

say "Cloud Billing budget for $PROJECT_ID"
gcloud services enable billingbudgets.googleapis.com --project="$PROJECT_ID"
BILLING_ACCOUNT="$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingAccountName)' | sed 's#billingAccounts/##')"
if gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" --billing-project="$PROJECT_ID" \
    --format='value(displayName)' | grep -qxF "$BUDGET_NAME"; then
  echo "  already exists"
else
  gcloud billing budgets create --billing-account="$BILLING_ACCOUNT" --billing-project="$PROJECT_ID" \
    --display-name="$BUDGET_NAME" --budget-amount="$BUDGET_AMOUNT" --calendar-period=month \
    --filter-projects="projects/$PROJECT_ID" \
    --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0 \
    --threshold-rule=percent=1.0,basis=forecasted-spend >/dev/null
  echo "  created: $BUDGET_AMOUNT/month, alerts at 50/90/100% and forecast 100%"
fi
