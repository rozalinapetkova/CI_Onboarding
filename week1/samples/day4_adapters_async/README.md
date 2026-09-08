# Day 1.4 samples — async / internal adapters

Samples for splitting `roi_<initials>_CustomerEchoService` into a main iFlow + a `roi_<initials>_CustomerLogger` consumer connected via **ProcessDirect**, with a **Data Store Write** keyed by `${header.customerId}`.

| File | Purpose |
|---|---|
| `processdirect_handoff.md` | ProcessDirect adapter config — both sides, headers allow-list, properties gotcha |
| `data_store_config.md` | `CustomerEcho` data store settings (key, retention, encryption) |
| `roiam_writeCustomerLog.groovy` | Consumer-side script that builds the log entry payload |
| `customer_logger_iflow.iflw.xml` | Skeleton iFlow XML for the consumer (ProcessDirect sender → Script → Data Store Write → End) |
| `data_store_entry_sample.json` | What ends up in the Data Store after a happy-path call |
| `sftp_polling_config.md` | Bonus: SFTP sender baseline (read locks, post-processing) — not used in the lab but introduced on Day 1.4 |
| `jms_limits_cheatsheet.md` | JMS Standard plan limits + when to pick JMS over ProcessDirect |
