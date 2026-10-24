## 0.1.0 (unreleased)

- TLV codec for all RSCP types, standard and compact frame headers, CRC-32.
- Full tag table (3,551 tags) generated from python-e3dc.
- `PortalTransport`: RSCP over the E3/DC portal websocket relay, including the 2026 protocol-version handshake.
- `E3dcClient`: live snapshot, system info, power settings, database summary.
- `DbSummary`: grid fields named `gridPurchaseWh` (DB_GRID_POWER_OUT) and `gridFeedInWh` (DB_GRID_POWER_IN), verified against autarky.
- Portal transport: responses on the virtual connection are no longer mistaken for handshake messages.
