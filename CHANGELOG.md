## 0.1.0 (unreleased)

- TLV codec for all RSCP types, standard and compact frame headers, CRC-32.
- Full tag table (3,551 tags) generated from python-e3dc.
- `PortalTransport`: RSCP over the E3/DC portal websocket relay, including the 2026 protocol-version handshake.
- `E3dcClient`: live snapshot, system info, power settings, database summary.
- `DbSummary`: grid fields named `gridPurchaseWh` (DB_GRID_POWER_OUT) and `gridFeedInWh` (DB_GRID_POWER_IN), verified against autarky.
- Portal transport: responses on the virtual connection are no longer mistaken for handshake messages.
- `E3dcClient.wallbox()` and `detectWallboxes()`: presence via WB_DEVICE_STATE / WB_APP_SOFTWARE.
- `E3dcClient.pvTrackers()`: all DC inputs of all inverters with live values, lifetime energy, the reported `PVI_DC_MAX_POWER` (`reportedMaxPowerW`, neither a hard limit nor module power) and an `active` flag based on measurements instead of `PVI_USED_STRING_COUNT`.
- `E3dcClient.dbHistory()`: database time series (sum plus raw `DbBucket`s per interval); `dbSummary()` now uses it. `example/db_history.dart` checks the bucket unit on a real unit.
- `LocalTransport`: direct RSCP over TCP with Rijndael-256-CBC (own implementation, checked against py3rijndael vectors), chained IVs across messages, frame reassembly over arbitrary TCP chunks, auth errors for a wrong portal login or RSCP password.
