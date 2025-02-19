#!/usr/bin/env bash
set -e

topdir="/volume1/Unencrypted/CESM_github_backups"
cd "${topdir}"

# Process argument(s)
org_repo="${1:-ESCOMP/CESM}"
todaysdir="${2:-CESM_repos_$(date "+%Y%m%d%H%M%S")}"
indentation="$3"
mkdir -p "${todaysdir}"

# grep wrapper that will not error if no matches are found
# https://stackoverflow.com/a/49627999/2965321
c1grep() { grep "$@" || test $? = 1; }

# Return 1 if org/repo is malformed, 0 otherwise
is_malformed() { [[ "$@" != *"/"* ]] && echo 1 || echo 0; }

# Skip if already done (and be case-insensitive about it)
d="${todaysdir}/${org_repo}"
exists="$(find "${todaysdir}" -mindepth 2 -maxdepth 2 -type d -iwholename "${d}" | wc -l)"
if [[ "${exists}" -ne 0 ]]; then
    #echo "Already got ${org_repo}."
    exit 0
fi
d="$(realpath ${topdir})/${d}"

# Skip if malformed
if [[ $(is_malformed ${org_repo}) -ne 0 ]]; then
    echo "${indentation}Skipping malformed org/repo ${org_repo}"
    exit 0
fi

# Print info
if [[ "${indentation}" == "" ]]; then
    echo "Saving to '$(realpath "${todaysdir}")'"
fi
echo "${indentation}Getting ${org_repo}..."

# Make directory
mkdir -p "${d}"
cd "${d}"
d="$PWD"

# Set up log file
logfile="${d}/backup.log"
touch "${logfile}"
logfile="$(realpath "${logfile}")"

# Back up (some) GitHub stuff
"${topdir}"/backup_github.sh 1>>"${logfile}" 2>&1

# Mirror the git stuff
ssh_url="git@github.com:${org_repo}.git"
git clone --mirror ${ssh_url} clone/.git  1>>"${logfile}" 2>&1
cd clone
git config --bool core.bare false 1>>"${logfile}" 2>&1
main_branch="$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')"
git checkout "${main_branch}" 1>>"${logfile}" 2>&1

# Download git-lfs files
set +e
git lfs fetch --all 1>>"${logfile}" 2>&1
result=$?
set -e
if [[ ${result} -ne 0 ]]; then
    msg="${indentation}Warning: problem with 'git lfs fetch --all' in ${org_repo} (error code ${result}). Skipping Git LFS download."
    echo "${msg}"
    echo "${msg}" 1>>"${logfile}" 2>&1
else
    git lfs pull 1>>"${logfile}" 2>&1
    git lfs checkout 1>>"${logfile}" 2>&1
fi

# Back up all submodules in .gitmodules for every branch
if [[ "$(git rev-list -n 1 --all -- .gitmodules | wc -l)" -gt 0 ]]; then
    # ↑ i.e., .gitmodules exists on any branch
    default_branch="$(git rev-parse --abbrev-ref HEAD)"
    branches="$(git for-each-ref --format='%(refname:short)' refs/heads/)"
    for b in ${branches}; do

        # Check out the branch
        git checkout $b 1>>"${logfile}" 2>&1
        if [[ ! -f .gitmodules ]]; then
            continue
        fi

        # Get all the repos linked in .gitmodules
        submodule_org_repos="$(grep -E "\burl = " .gitmodules | grep -oE "https://.*" | cut -d"/" -f4-5 | sed -E "s/\.git$//")"

        # Manually add a few that aren't in .gitmodules anywhere
        manually_added_list=""
        if [[ "${org_repo}" == "ESCOMP/CESM" ]]; then
            manually_added_list="ESMCI/git-fleximod ESCOMP/CAM-SIMA"
            submodule_org_repos="${manually_added_list} ${submodule_org_repos}"
        fi

        # Download all submodules
        for submodule_org_repo in ${submodule_org_repos}; do

            # Skip if malformed
            if [[ $(is_malformed ${submodule_org_repo}) -ne 0 ]]; then
                echo "${indentation}---Skipping malformed org/repo ${submodule_org_repo}"
                continue
            fi

            # This script assumes submodules are hosted on github.com
            on_github=$(c1grep -E "github.com[:/]${submodule_org_repo}" .gitmodules | wc -l)
            was_manually_added=$(echo ${manually_added_list} | c1grep -E "\b${submodule_org_repo}\b" | wc -l)
            if [[ $((on_github + was_manually_added)) -eq 0 ]]; then
                msg="${submodule_org_repo} is hosted somewhere other than github.com: $(grep ${submodule_org_repo} .gitmodules)"
                echo ${msg} >&2
                echo ${msg} >> "${logfile}"
                exit 1
            fi

            # Sometimes the URL ends in .git, which we don't want
            if [[ "${submodule_org_repo}" == *".git" ]]; then
                submodule_org_repo="$(echo ${submodule_org_repo} | sed -E "s/\.git$//")"
            fi

            # Make sure repo actually exists
            set +e
            git ls-remote git@github.com:${submodule_org_repo} 1>/dev/null 2>&1
            result=$?
            set -e
            if [[ ${result} -ne 0 ]]; then
                msg="WARNING: github.com/${org_repo} doesn't seem to exist. Skipping."
                echo "${indentation}${msg}"
                echo ${msg} >> "${logfile}"
                continue
            fi

            # Back up this repo
            "${topdir}"/backup_recursive.sh ${submodule_org_repo} "${todaysdir}" "${indentation}---"
        done
        git stash 1>/dev/null
    done
    git checkout ${default_branch} 1>>"${logfile}" 2>&1
fi

echo "${indentation}Done with ${org_repo}!"

exit 0
