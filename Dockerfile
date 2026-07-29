# Dev-only image. Everything runs local, no deploy target yet.
FROM elixir:1.20.2-slim AS base

RUN apt-get update -y && apt-get install -y --no-install-recommends \
      build-essential git curl ca-certificates openssl libncurses6 locales \
      inotify-tools postgresql-client \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /app

FROM base AS dev
# Source, deps and build artifacts come in through compose volumes; the
# entrypoint fetches deps, sets up the DB and starts the server.
CMD ["bash", "bin/dev-entrypoint.sh"]
