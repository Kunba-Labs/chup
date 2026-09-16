# Chup! trusted development backend

Node 22+. Run `npm ci`, copy `.env.example` to `.env`, enter the server-only OpenAI key and an independently generated app token, then `npm start`. The server binds loopback. The app uses the app token; it never receives the OpenAI project secret. Configure the app token with `CHUP_TOKEN` in the backend environment.

The REST request header `X-Chup-Request-ID` activates a durable encrypted provider-step journal. The native app always supplies it. A repeated ID with the same payload reuses completed work; changed content is rejected. An interrupted provider call with unknown acceptance is not automatically billed again. Replays of deleted requests are blocked. Legacy requests without the header have no replay guarantee.

`CHUP_JOURNAL_DIR` defaults to backend/.data. That directory contains an AES-GCM journal and its filesystem key (0700 directory / 0600 key and records). Keep it on a trusted encrypted volume and back it up securely. It is independent of the Mac app's Keychain. Each token has a hashed namespace. Deploy only one backend process for this directory; cross-process/distributed locking is not implemented. Production needs per-user authentication, quotas, protected key management, HTTPS and operational monitoring.

`CHUP_JOURNAL_RETENTION_DAYS` defaults to 30; startup and hourly maintenance strip expired response content. Authenticated `/forget` accepts the native app's opaque request IDs and creates replay-prevention tombstones; these contain no cached response or audio. Content already sent to OpenAI remains subject to provider data controls. No meeting text/audio is written to logs, but provider responses are intentionally cached encrypted for recovery.

Usage metadata is returned in `_chup.usage`. It contains provider units and raw usage, not an invented bill. Final Live snapshots, completed transcription item usage and backend response usage have separate scopes. Missing provider usage remains unconfirmed. Real account access and billing reconciliation have not been tested.

Run `npm test` for evidence, routing contracts, HTTP fixtures and crash/replay/deletion tests. These use fixtures, not production provider calls.

## Bounded real-provider qualification

With OPENAI_API_KEY already set on this trusted host, run from the repository root:

```sh
python3 scripts/prepare-provider-fixtures.py
node backend/qualify-provider.mjs --run
```

This invokes real billable APIs with synthetic English/Dutch speech only. It creates an isolated relay token/journal and writes `.artifacts/provider-qualification.json`. No mic, speakers, personal app database or real recordings are used. Without `--run`, only account model access is checked. Results do not certify speaker identity, accuracy on real calls or private audio routing. The fixture uses macOS `say` voices Samantha and Xander.

Run one server process per journal directory. Cross-process request arbitration is not implemented. Keep `journal.key` with its encrypted jobs in trusted-host backups. A missing key now blocks opening existing namespaces instead of silently generating a replacement.
