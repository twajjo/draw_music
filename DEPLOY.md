# Deploying Draw Music

One Elixir release and one `Dockerfile` serve every target. Each host has its own small config file:

| Target | Build | Config |
|---|---|---|
| Own server | `Dockerfile` with Postgres alongside | `docker-compose.yml`, `.env` |
| Fly.io | `Dockerfile` | `fly.toml` |
| Render | `Dockerfile` | `render.yaml` |
| Gigalixir | its buildpacks (`mix release`) | `elixir_buildpack.config`, `phoenix_static_buildpack.config`, `compile` |

## What every target needs

| Variable | |
|---|---|
| `DATABASE_URL` | `ecto://USER:PASS@HOST/DATABASE` (hosted Postgres sets it for you) |
| `SECRET_KEY_BASE` | `mix phx.gen.secret` (64+ bytes) |
| `PHX_HOST` | the public host name, e.g. `draw-music.fly.dev` |
| `PORT` | the port to listen on (default 4000) |
| `DATABASE_SSL` | `true` when the database only takes SSL connections |
| `ECTO_IPV6` | `true` on an IPv6-only private network (Fly) |
| `SAMPLES_DIR` | optional: a writable directory for the instrument samples |
| `POOL_SIZE` | optional: database connections (default 10) |

- **Migrations** run with `bin/migrate` before each new version starts. Fly and Render do this through their release and pre-deploy commands; Docker Compose does it on every start.
- **Health check:** `GET /health` answers 200 `ok` and is exempt from the HTTPS redirect.
- **Instrument samples** (about 72 MB) are downloaded while the image builds (`mix samples.fetch`) and ship inside the release, so no host needs a disk for them. A volume, with `SAMPLES_DIR` pointing at it, only matters if admins will fetch more instruments after deploy. Copy the built-in ones there first, or fetch them again.

## Own server (Docker Compose)

```sh
cp .env.example .env        # fill in SECRET_KEY_BASE and PHX_HOST
docker compose up -d --build
```

The app listens on port 4000. Put Caddy, nginx or Traefik in front of it for HTTPS, passing `X-Forwarded-Proto` so the HTTPS redirect knows the request was secure.

Plain Docker without Compose:

```sh
docker build -t draw-music .
docker run --rm -e DATABASE_URL=… -e SECRET_KEY_BASE=… -e PHX_HOST=… draw-music /app/bin/migrate
docker run -d -p 4000:4000 -e DATABASE_URL=… -e SECRET_KEY_BASE=… -e PHX_HOST=… draw-music
```

## Fly.io

```sh
fly launch --no-deploy          # keeps fly.toml; pick the app name and region
fly postgres create             # or Fly's managed Postgres
fly postgres attach <db-app>    # sets DATABASE_URL
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
fly deploy
```

If you rename the app, change `PHX_HOST` in `fly.toml` to match. `release_command` runs the migrations. For on-demand instruments, uncomment `[mounts]` and `SAMPLES_DIR` in `fly.toml` after `fly volumes create samples --size 1`.

## Render

1. Push the repository to GitHub, then choose **New → Blueprint** in the Render dashboard and pick it. `render.yaml` creates the web service and its Postgres.
2. Set `SECRET_KEY_BASE` by hand (`mix phx.gen.secret`). Render's generated values are shorter than the 64 bytes Phoenix needs.
3. If the service name changes, set `PHX_HOST` to its `onrender.com` name.

`preDeployCommand` runs the migrations. A persistent disk (paid) is only needed for on-demand instruments; see the comment in `render.yaml`.

## Gigalixir

Gigalixir builds from source with buildpacks rather than the Dockerfile. `elixir_buildpack.config` and `phoenix_static_buildpack.config` pin the same versions as `mise.toml`, and `compile` builds the assets and fetches the samples.

```sh
gigalixir create -n draw-music
gigalixir pg:create --free
gigalixir config:set SECRET_KEY_BASE=$(mix phx.gen.secret) PHX_HOST=draw-music.gigalixirapp.com DATABASE_SSL=true
git push gigalixir master
gigalixir ps:migrate
```

Not yet tried on Gigalixir:
- whether its buildpacks offer Erlang 29.1.2, Elixir 1.20.4 and Node 23.8.0;
- whether its database needs `DATABASE_SSL=true` (assumed above);
- how `ps:migrate` works in release mode.

Gigalixir has no persistent disk, so instruments fetched after deploy would be lost on the next deploy; the built-in ones are unaffected.
