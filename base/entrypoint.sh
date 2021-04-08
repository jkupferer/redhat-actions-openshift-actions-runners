
#!/bin/sh
# Based on https://github.com/bbrowning/github-runner/blob/master/entrypoint.sh

./uid.sh > /tmp/uid.sh.log

set -eE

if [ -z "${GITHUB_OWNER:-}" ]; then
    echo "Fatal: \$GITHUB_OWNER must be set in the environment"
    exit 1
elif [ -z "${GITHUB_PAT:-}" ]; then
    echo "Fatal: \$GITHUB_PAT must be set in the environment"
    exit 1
fi

if [ -z "${GITHUB_DOMAIN:-}" ]; then
    echo "Connecting to public GitHub"
    GITHUB_DOMAIN="github.com"
else
    echo "Connecting to GitHub server at '$GITHUB_DOMAIN'"
fi

if [ -z "${GITHUB_REPOSITORY:-}" ] && [ -n "${GITHUB_REPO:-}" ]; then
    GITHUB_REPOSITORY=$GITHUB_REPO
fi

# https://docs.github.com/en/free-pro-team@latest/rest/reference/actions#create-a-registration-token-for-an-organization

registration_url="https://${GITHUB_DOMAIN}/${GITHUB_OWNER}"
if [ -z "${RUNNER_TOKEN:-}" ]; then
    if [ -z "${GITHUB_REPOSITORY:-}" ]; then
        echo "Runner is scoped to organization '${GITHUB_OWNER}'"
        echo "View runner status at https://${GITHUB_DOMAIN}/organizations/${GITHUB_OWNER}/settings/actions"

        token_url="https://api.${GITHUB_DOMAIN}/orgs/${GITHUB_OWNER}/actions/runners/registration-token"
    else
        echo "Runner is scoped to repository '${GITHUB_OWNER}/${GITHUB_REPOSITORY}'"
        echo "View runner status at https://${GITHUB_DOMAIN}/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/settings/actions"

        token_url="https://api.${GITHUB_DOMAIN}/repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/actions/runners/registration-token"
        registration_url="${registration_url}/${GITHUB_REPOSITORY}"
    fi
    echo "Obtaining runner token from ${token_url}"

    payload=$(curl -sSfLX POST -H "Authorization: token ${GITHUB_PAT}" ${token_url})
    export RUNNER_TOKEN=$(echo $payload | jq .token --raw-output)
    echo "Obtained registration token"
else
    echo "Using RUNNER_TOKEN from environment"
fi

labels_arg=""
if [ -n "${RUNNER_LABELS:-}" ]; then
    labels_arg="--labels $RUNNER_LABELS"
else
    echo "No labels provided"
fi

set -x
./config.sh \
    --name $(hostname) \
    --token ${RUNNER_TOKEN} \
    --url ${registration_url} \
    --work ${RUNNER_WORKDIR} \
    ${labels_arg} \
    --unattended \
    --replace
set +x

remove() {
    payload=$(curl -sSfLX POST -H "Authorization: token ${GITHUB_PAT}" ${token_url%/registration-token}/remove-token)
    export REMOVE_TOKEN=$(echo $payload | jq .token --raw-output)

    ./config.sh remove --unattended --token "${REMOVE_TOKEN}"
}

trap 'remove; exit 130' INT
trap 'remove; exit 143' TERM

set -x
./bin/runsvc.sh --once &
svc_pid=$!

wait $svc_pid
