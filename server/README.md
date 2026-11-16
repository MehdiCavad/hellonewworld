# Rankd server (.NET 10)

Three projects plus tests, in `Rankd.slnx`:

| Project | What it is | Dev URL |
|---|---|---|
| `src/Rankd.Core` | Domain entities and the ranking engine (Bradley–Terry fit, adaptive pairing). No dependencies. | |
| `src/Rankd.Infrastructure` | EF Core 10 (SQL Server, Sqlite for dev), catalogue seeder, session sync, community ranking job, media ingestion. | |
| `src/Rankd.Api` | Public Web API for the app, under `/api/v1`. OpenAPI + Scalar docs at `/docs` in Development. | http://localhost:5080 |
| `src/Rankd.Admin` | Admin panel, Blazor Server. Internal network only. | http://localhost:5090 |
| `tests/Rankd.Tests` | Engine parity tests against the prototype, plus API tests on a temporary Sqlite file. | |

## Run it locally

Needs the .NET 10 SDK. Development uses a Sqlite file (`server/rankd-dev.db`), so no SQL Server is required,
and seeds the catalogue plus a few hundred demo sessions so the dashboards have something to show.

```bash
cd server
dotnet test                                   # 41 tests
ASPNETCORE_ENVIRONMENT=Development dotnet run --project src/Rankd.Api   --urls http://localhost:5080
ASPNETCORE_ENVIRONMENT=Development dotnet run --project src/Rankd.Admin --urls http://localhost:5090
```

## Production (SQL Server)

1. Set `ConnectionStrings:Rankd` for both the API and the admin (environment variable `ConnectionStrings__Rankd`).
2. Create the schema. Either let the API migrate on start (`Database:MigrateOnStartup=true`), or hand a DBA the script:
   ```bash
   dotnet tool restore
   RANKD_SQLSERVER="<connection string>" dotnet ef migrations script --idempotent \
     --project src/Rankd.Infrastructure --startup-project src/Rankd.Infrastructure -o rankd.sql
   ```
3. Keep `Database:SeedDemoActivity` **false** outside development.
4. Restrict the admin with `Admin:AllowedNetworks` (CIDR list). Requests from anywhere else get 404.
   There is no login, by design (scope v0.2): network placement is the access control.

## API at a glance

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v1/levels` | The four levels |
| GET | `/api/v1/topics` | Active topics with item counts per tier |
| GET | `/api/v1/topics/{slug}` | Items and enabled media; supports `ETag` / `304` |
| GET | `/api/v1/topics/{slug}/global-ranking?take=` | Community ranking, with previous rank |
| GET | `/api/v1/attributions` | Media providers and licence notices |
| PUT | `/api/v1/sessions/{id}` | Idempotent upload of a whole session (header `X-Rankd-Device`) |
| GET | `/api/v1/sessions` | This device's sessions |
| DELETE | `/api/v1/devices/me` | Deletes the device and everything it uploaded |

The device id is an anonymous UUID the app creates on first launch. Community rankings are recomputed in the
background and ignore sessions with fewer than 5 answers, answers faster than 400 ms, and cap each device at 300 answers.

## Media

Images and previews are hotlinked, never re-hosted. Each asset records its provider, licence and attribution,
and can be switched off from the admin's Media page. Ingestion pulls from Wikipedia / Wikimedia Commons and the
iTunes Search API; run it from the admin's Topics page.
