# Import first, classify later

Native Google Sheets: Import Statements opens device selection directly, without a source-options dialog. Android uses ACTION_OPEN_DOCUMENT without CATEGORY_OPENABLE, allowing Drive virtual documents. It requests an XLSX/CSV export using openTypedAssetFileDescriptor, reads off the UI thread, and caps downloads at 20 MB. Access is limited to the selected document's URI read grant. Computers can select synced .gsheet shortcuts: the app extracts only the embedded Sheets ID and loads worksheets with the existing authenticated reader. No link entry is required. Local file choosers cannot browse cloud-only Sheets on the web; a Google Picker integration is separate future work. Sources are never changed and source IDs never replace the destination ledger. Both paths retain confirmation, duplicate checks and classification.

Google authorization uses `drive.file`, not full Sheets or Drive access. A
`.gsheet` shortcut alone does not grant the app per-file access; if Google denies
access, export the statement as CSV or XLSX. Reading arbitrary Sheets without a
Google Picker grant would require a broader Sheets scope, which is not requested.
The app persists the ledger ID per account. For older installs and new devices
without a saved ID, it performs a one-time Drive lookup restricted to owned,
app-accessible spreadsheets named exactly `Expense Tracker DB`; ambiguous
matches stop sync rather than selecting a file arbitrarily. All subsequent
ledger operations use the saved ID. A missing or inaccessible import target
does not cause the Worker to create a replacement.

Deploy the updated Worker before releasing this app; older Workers can create a
replacement sheet. Existing Google grants may still include the old Sheets scope
until the user revokes Pocket Ledger access in their Google account and signs in
again. Remove the broad scope from the Google Cloud OAuth consent configuration
as well; that external configuration is not changed by this repository.

Statement confirmation shows dates, descriptions, amounts and duplicate status by default. No classification is required. Optional individual category/type edits and existing duplicate safeguards remain available. Unedited duplicate rows are skipped even if an inherited merchant category differs. Successful imports offer Classify merchants, opening Financial Baseline's remaining merchant view. Individual transaction overrides remain higher priority than merchant choices.

Financial Baseline summarizes classified, unclassified, and excluded merchants by count and eligible spending. The segmented bar and its legend show each group's percentage of total eligible spending. Expand a group to review or edit its merchants. When switching or collapsing a group with pending edits, save or ignore those edits to continue, or cancel to keep working. Savings insights shows the Essentiality and Category charts below the monthly averages; chart totals use all eligible history, so they can differ from the averages.

The existing API already reuses saved merchant categories and expense types for future imports. Essentiality is inherited from the saved merchant rule when transactions are loaded. No new Gmail code or scope is involved.

Bulk exclusion now saves an account-scoped small-merchant policy and the chosen threshold in Merchant Classifications. On full committed-ledger synchronization after import/refresh, unclassified merchants with total spending strictly below the chosen amount receive NA defaults. New merchants are eligible too. At or above the threshold, existing exclusions become Uncategorized / Unknown / Unclassified and return to review. Whole-ledger totals use the same grouping/deduplication/refund handling as Financial Baseline, not the current statement alone. This does not rewrite amounts or dates. Explicit transaction exceptions and fully classified merchants are preserved.

Once a merchant crosses the threshold it stays in review until the user acts, even if later spending/refunds reduce its total. Remove NA opts that merchant out of future automatic exclusion. Changing the saved limit updates still-excluded merchants; it does not overwrite confirmed classifications. Policies are evaluated only against a full ledger, never a filtered preview or incomplete cache.

Earlier NA records did not persist their original limit. That value cannot be recovered safely: users must save their chosen limit once in Bulk Exclude Small Merchants to adopt older exclusions into automatic checking. No amount is silently guessed.

If Sheets synchronization fails, the import remains saved and classification synchronization retries on refresh. Rules are applied after committed imports, so cancellation, rejected imports and duplicate reimports never count toward the threshold.

Bulk-exclusion UI: the action appears in Unclassified when at least one unclassified merchant has total spending of 100 or more in the selected currency. It is collapsed by default; the visibility threshold is separate from the user-entered exclusion limit. Opening it shows Exclude all merchants <, the amount input and Exclude. Validation errors and the existing >25% transaction-impact warning appear only when applicable. A successful save shows a brief confirmation with the chosen amount.
