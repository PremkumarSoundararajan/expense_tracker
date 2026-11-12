# Email scanning retired

The complete Gmail feature and tests are preserved on branch `experimentEmailScan`. Production main has no mailbox connection, scan button, Gmail permissions, or scan reminders. Upgrades cancel legacy notification 831 and clear scan-reminder preferences; ordinary expense reminders are unchanged.

A dismissible privacy notice and persistent Settings privacy update explain retirement and link to Google Account connections. Existing Sheets expenses remain unchanged. Old API clients and OAuth callbacks are rejected. See the API repository docs/email-retirement.md for provider revocation and cleanup verification. Future experimentation requires a separate test deployment and explicit new authorization.
