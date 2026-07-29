#!/usr/bin/env bash
# One command brings the whole dev stack up: deps, DB, server.
set -euo pipefail

mix local.hex --force --if-missing
mix local.rebar --force --if-missing

echo "== mix deps.get =="
mix deps.get

echo "== database setup =="
mix ecto.create
mix ecto.migrate

echo "== phx.server =="
exec mix phx.server
