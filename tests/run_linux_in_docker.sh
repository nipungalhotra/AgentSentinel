#!/usr/bin/env bash
# Runs the Linux end-user scenario in throwaway Docker containers (Ubuntu 24.04 and Python 3.9),
# installing loggdin from the portable zip as a normal user. Needs Docker (e.g. `colima start`).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/packaging/create_portable.sh" >/dev/null
ZIP="$(ls "$ROOT"/dist/loggdin-portable-v*.zip | head -1)"
status=0
for image in ubuntu:24.04 python:3.9-slim; do
  echo "=================== $image"
  cid=$(docker run -d "$image" sleep infinity)
  trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
  docker exec "$cid" sh -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 unzip curl procps >/dev/null 2>&1 || true; command -v python3 || ln -s /usr/local/bin/python3 /usr/bin/python3; useradd -m -s /bin/bash dev; mkdir /work'
  docker cp "$ZIP" "$cid:/work/loggdin.zip"
  docker cp "$ROOT/tests/linux_scenario.sh" "$cid:/work/scenario.sh"
  docker exec "$cid" chown -R dev /work
  if docker exec -u dev -w /home/dev -e LOGGDIN_ZIP=/work/loggdin.zip "$cid" sh /work/scenario.sh; then
    echo "✅ $image passed"
  else
    echo "❌ $image failed"; status=1
  fi
  docker rm -f "$cid" >/dev/null
done
exit $status
