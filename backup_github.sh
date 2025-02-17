#!/usr/bin/env bash
set -e

# Back up Github stuff
for element in discussions issues pulls; do
    url="https://api.github.com/repos/${org_repo}/${element}"
    curl -H "Accept: application/vnd.github.v3+json" "${url}" > "${element}.json"
done


exit 0