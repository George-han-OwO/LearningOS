## 1.0.0

- Initial version.

## 1.1.0

- Store DeepSeek API keys with AES-256-GCM authenticated encryption.
- Migrate legacy plaintext keys at startup when the server master key is configured.
- Add a server-owned 30-second pending-word enrichment worker and API endpoints.
- Keep Android/Windows clients from receiving provider secrets.
