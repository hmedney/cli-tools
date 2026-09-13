#!/usr/bin/env bash

# Common container launch script.

SCRIPT_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
COMPOSE_FILE="${SCRIPT_DIR}/internal/compose/compose.yaml"
CURRENT_HOME="${HOME}"
CURRENT_USERNAME=$(id -u -n)
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

if [ "${PWD}" = "${CURRENT_HOME}" ]; then
  echo "tool cannot be run from \$HOME (${CURRENT_HOME})."
  echo "Please cd into a project directory and try again."
  exit 1
fi

function with_env() {
  # provide service name and host env vars for ezch docker compose invocation
  COMPOSE_SERVICE="${COMPOSE_SERVICE}" CURRENT_USERNAME="${CURRENT_USERNAME}" CURRENT_UID="${CURRENT_UID}" CURRENT_GID="${CURRENT_GID}" CURRENT_HOME="${CURRENT_HOME}" "$@"
}

# host dir for this tool's home dir.
# $HOST_TOOL_HOME is mounted as the tool's home dir inside the container.
HOST_TOOLS_HOME="${HOME}/cli-tools"
HOST_TOOL_HOME="${HOST_TOOLS_HOME}/${COMPOSE_SERVICE}"
mkdir -p "${HOST_TOOL_HOME}"

# path in container that will be set to HOME (cli tools will write their local files here). this is mounted as $HOST_TOOL_HOME
CONTAINER_TOOL_HOME="${HOME}/cli-tool"

case "$1" in
  :build)
    echo "Building ${COMPOSE_SERVICE}..."
    with_env docker compose --file "${COMPOSE_FILE}" build ${COMPOSE_SERVICE}
    exit 0
    ;;
  :build-verbose)
    echo "Building ${COMPOSE_SERVICE}..."
    with_env docker compose --file "${COMPOSE_FILE}" build ${COMPOSE_SERVICE} --progress plain
    exit 0
    ;;
  :rebuild)
    echo "Rebuilding ${COMPOSE_SERVICE}..."
    with_env docker compose --file "${COMPOSE_FILE}" build ${COMPOSE_SERVICE} --no-cache
    exit 0
    ;;
  :upgrade)
    # perform an upgrade by re-running just the cli tool install layer
    echo "Upgrading ${COMPOSE_SERVICE}..."
    with_env docker compose --file "${COMPOSE_FILE}" build ${COMPOSE_SERVICE} --build-arg UPGRADE_CACHE_BUST=$(date +%s)
    exit 0
    ;;
  :shell)
    echo "Entering shell..."
    with_env docker compose --file "${COMPOSE_FILE}" run --rm --entrypoint /bin/bash ${COMPOSE_SERVICE}
    ;;
  :exec)
    echo "Entering exec into ${COMPOSE_SERVICE}..."
    IDS=$(docker ps --filter "label=com.docker.compose.service=${COMPOSE_SERVICE}" --filter "status=running" --quiet)
    COUNT=$(printf '%s\n' "${IDS}" | grep -c .)
    case "${COUNT}" in
      1)
        FIRST_ID=$(printf '%s\n' "${IDS}" | head -n1)
        docker exec -it "${FIRST_ID}" /bin/bash
        ;;
      0)
        echo "${COMPOSE_SERVICE} is not currently running."
        echo "Launch it first, or use ':shell' to start a fresh container."
        ;;
      *)
        echo "${COUNT} instances of ${COMPOSE_SERVICE} are running; can't pick one:"
        printf '%s\n' "${IDS}"
        echo "Stop the extras and try again."
        ;;
    esac
    exit 0
    ;;
  :watch)
    echo "Tailing http proxy requests..."
    with_env docker compose --file "${COMPOSE_FILE}" exec gateway lnav /var/log/squid/access.log
    exit 0
    ;;
  :help)
    echo "Meta commands: :build, :build-verbose, :rebuild, :upgrade, :shell, :exec, :watch"
    exit 0
    ;;
  *)
    # No meta-command, so we proceed as normal with "$@" intact
    ;;
esac

SSH_MOUNT=()
if [ -n "${SSH_AUTH_SOCK:-}" ]; then
  SSH_MOUNT=(
    --volume "${SSH_AUTH_SOCK}:/tmp/ssh-agent.sock"
    --env "SSH_AUTH_SOCK=/tmp/ssh-agent.sock"
  )
fi

GIT_MOUNT=()
if [ -f "${HOME}/.gitconfig" ]; then
  GIT_MOUNT=(--volume "${HOME}/.gitconfig:/etc/gitconfig:ro")
fi

ENV_FILE=()
if [ -f "${HOST_TOOL_HOME}/.env" ]; then
  ENV_FILE=(--env-from-file "${HOST_TOOL_HOME}/.env")
fi

with_env docker compose --file "${COMPOSE_FILE}" run --rm -it \
  --service-ports \
  --user "${CURRENT_UID}:${CURRENT_GID}" \
  --volume "${PWD}:${PWD}" \
  --volume "${HOST_TOOL_HOME}:${CONTAINER_TOOL_HOME}" \
  --env HOME="${CONTAINER_TOOL_HOME}" \
  "${ENV_FILE[@]}" \
  "${GIT_MOUNT[@]}" \
  "${COMPOSE_SERVICE}" \
  "$@"

# docker compose --file "${COMPOSE_FILE}" stop gateway
