# Bruno API Collections

[What is Bruno?](https://www.usebruno.com/)

Ready-to-use Bruno collection for the Scalekit API. This is the same collection used internally for testing and ships with full request sequences, environments, and coverage of the current public surface (Organizations, Clients/M2M, Connections, Users, Directory/SCIM, Connected Accounts, MCP, Roles & Permissions, Tokens, Interceptors, Secrets, Sessions, etc.).

## Layout

- Numbered files (e.g. `01_create_...`, `02_...`) indicate suggested execution order for complete flows.
- Run `run.sh` (or open the collection in Bruno) after configuring an environment.
- `environments/` contains ready configs for local, staging, US prod, EU prod.

## Getting started

1. Open Bruno and import (or open) the `bruno/` folder as a collection.
2. Duplicate one of the environment files and fill in your Scalekit credentials (subdomain + API key / client secret).
3. Start with the "Getting Started" style flow or any `01_create_org` + follow-ups.

The collection is kept in sync from the authoritative copy in the Scalekit backend via the script in the `feedback-syndicate` meta-repo. See the root README for import instructions and the latest OpenAPI spec.
