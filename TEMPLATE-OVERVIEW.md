# Deploy and Host LiteLLM on Railway

LiteLLM puts one OpenAI-compatible address in front of every model provider you use. Point your application at it once, and switch providers, split traffic, cap spend or revoke a colleague's access without touching application code.

This template deploys it the way it is meant to run: the proxy, Postgres for keys and spend, Redis for shared limits and cache. Pinned versions, generated secrets, nothing left to wire.

## About Hosting LiteLLM

Self-hosted AI gateways are among the fastest-growing deployments on Railway right now — and among the fastest-failing. The most popular one collected 1700 installs in six weeks with roughly a third never coming up. LiteLLM, the mature option, is offered as a single container in every template that carries it, and a single container is exactly what it cannot be if you want the features people install it for.

Without Postgres there are no virtual keys, no budgets and no spend tracking — the proxy runs, and the reason you chose it is missing. Without Redis, rate limits are counted inside each process: run two replicas and each quietly enforces its own copy of the limit, so a key capped at 60 requests a minute gets 120. The cache has the same problem, and you pay for the duplicate calls.

## Common Use Cases

- **One key per person, with a budget.** Issue a virtual key to each developer or application, cap the monthly spend, and revoke it without rotating a provider key.
- **Provider failover.** Route a model group across two providers so an outage at one is not an outage for you.
- **A private endpoint for every tool.** Anything that speaks the OpenAI API — an SDK, an IDE plugin, a coding agent — points at your gateway and gets the model you decide, not the one it defaults to.

## Dependencies for LiteLLM Hosting

### Deployment Dependencies

- [LiteLLM](https://github.com/BerriAI/litellm) — the proxy, pinned to `ghcr.io/berriai/litellm-database:v1.93.0`
- Postgres — virtual keys, budgets, spend, and models added at runtime
- Redis — shared rate-limit counters and response cache
- [Template source](https://github.com/ak40u/litellm-railway-starter)

### Implementation Details

- **The image is pinned to an exact release.** LiteLLM ships several releases a week; a moving tag turns every restart into a lottery. The `-database` variant carries the Prisma toolchain, so the proxy migrates its own schema on first boot instead of needing a separate job.
- **Redis is wired into both places that need it** — `litellm_settings.cache_params` for the response cache and `router_settings` for rate limiting and retries. This is the difference between limits that hold across replicas and limits that each process invents on its own.
- **Models are stored in the database.** Add a provider in the UI and it survives redeploys, with the API key encrypted at rest under `LITELLM_SALT_KEY`.
- **`drop_params` is on**, so one client keeps working across models that accept different option sets instead of failing on an unknown parameter.
- **Every secret is generated** — master key, salt, UI password, database and Redis passwords. Nothing ships with a default credential.
- **Redis runs with a password, an append-only file on a volume, and dual-stack binding.** Railway's private network is IPv6; a Redis bound only to IPv4 is unreachable from the proxy, which is the failure most Redis templates ship with.
- **The health check is `/health/liveliness`**, which needs no credentials — a health path behind auth fails the deployment while the application is perfectly alive.

A `self-test` model ships with the template. It answers without calling any provider, so a fresh deployment can be verified before you have added a key — delete it once your own models are in. The repository also carries `scripts/verify-gateway.sh`, which issues a virtual key limited to one request per minute, spends it, confirms the second call is refused, reads the key back out of Postgres, and adds a model at runtime. This template was published only after that script passed against a deployment created from the template itself.

## Why Deploy LiteLLM on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying LiteLLM on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
