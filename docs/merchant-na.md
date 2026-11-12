> Current behavior: see [import-first.md](import-first.md). Exclusion is now a saved policy evaluated against committed ledger totals, replacing the earlier one-time behavior described below.

# Small-merchant NA workflow

In Financial Baseline, choose **Unclassified** and open **Bulk update small merchants as NA**
above the table. Enter a positive amount (minimum 0.01). The comparison uses each
normalized merchant's total positive net spending across all recorded history,
strictly less than the amount. Transfers follow the existing spending eligibility
rules. Zero and net-refund merchants are not selected.

The preview shows merchant and transaction counts, the dollar amount, and its
share of total spending. More than 25% of eligible transactions triggers an
informational advisory; it does not block Save NA.
Only unclassified merchants are eligible; completed classifications and existing
NA choices are preserved. Save or discard pending individual edits before using
the bulk save. The action is hidden in Classified and Review NA.

NA merchants have NA displayed for all three merchant defaults. The stored
category is NA, Expense Type is Unknown, and essentiality is Unclassified.
Actual spending is retained; NA is not assumed Regular, Planned, or Essential.
Explicit transaction exceptions still take precedence and remain visible.

The action saves merchant choices through the existing local outbox and Google
Sheets metadata/batched projection. Matching future transactions inherit them.
It is not a continuously evaluated threshold rule: new merchants remain
unclassified, and merchants do not automatically leave NA when their totals grow.

Saved NA merchants leave the classified/unclassified work lists and are available
via **Review NA**, with count and spending percentage. Use **Remove NA** in the
merchant menu, then Save changes. Previous choices for recorded transactions are
restored where available; unclassified choices can then be edited normally.

Home Maintenance is available in category pickers under Housing / Bills, including
accounts whose saved category configuration predates that choice. Its stable ID
is `housing-bills:home-maintenance`. Existing custom Home Maintenance choices are
reused by name rather than duplicated.
