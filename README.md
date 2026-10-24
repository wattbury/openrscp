# openrscp

Dart implementation of RSCP, the protocol of E3/DC home power stations (S10 family). Part of the [Wattbury](https://github.com/wattbury) project.

- TLV codec and frames (standard 18-byte header and the compact header introduced by the portal relay in 2026), CRC-32.
- `PortalTransport`: RSCP over the E3/DC portal websocket relay (`wss://s10.e3dc.com/ws`) with portal login and serial number. No VPN, no RSCP password. Undocumented by E3/DC, reverse-engineered after python-e3dc.
- `E3dcClient`: live values, system info, power settings, database summaries.
- Planned: `LocalTransport` (TCP 5033, Rijndael-256-CBC).

```bash
E3DC_USER=... E3DC_PASS=... E3DC_SN=S10-... dart run example/portal_live.dart
```

Values follow the device convention: grid > 0 is purchase, < 0 feed-in; battery > 0 charging, < 0 discharging. All power in W, energy in Wh.

## Credits and disclaimer

The RSCP tag table (`lib/src/tags.g.dart`) and the portal relay handshake are derived from
[python-e3dc](https://github.com/fsantini/python-e3dc) (MIT, Copyright (c) Francesco Santini and contributors),
whose tag list in turn was imported from E3/DC's public web portal script.

This project is not affiliated with or endorsed by E3/DC or HagerEnergy GmbH. "E3/DC" is a trademark of its owner.
The portal relay is undocumented and may change without notice. Use it only for your own system with your own credentials.

## License

MIT, see [LICENSE](LICENSE).
