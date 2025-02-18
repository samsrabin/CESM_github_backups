#!/usr/bin/env bash
set -e

topdir="/volume1/Unencrypted/CESM_github_backups"
cd "${topdir}"

# Process argument(s)
org_repo="${1:-ESCOMP/CESM}"
todaysdir="${2:-CESM_repos_$(date "+%Y%m%d%H%M%S")}"
mkdir -p "${todaysdir}"

# Skip if already done
d="$(realpath ${topdir})/${todaysdir}/${org_repo}"
if [[ -d "${d}" ]]; then
    cd "${d}"
    echo "Already got ${org_repo}."
	exit 0
fi

echo "Getting ${org_repo}..."

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
git config --bool core.bare false 1>"${logfile}" 2>&1
main_branch="$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')"
git checkout "${main_branch}" 1>>"${logfile}" 2>&1

# Download git-lfs files
git lfs fetch --all 1>>"${logfile}" 2>&1
git lfs pull 1>>"${logfile}" 2>&1
git lfs checkout 1>>"${logfile}" 2>&1


# Back up all submodules
cd "${d}/clone"
submodule_org_repos="$(grep -E "\burl = " .gitmodules | grep -oE "https://.*" | cut -d"/" -f4-5 | sed -E "s/\.git$//")"
for submodule_org_repo in ${submodule_org_repos}; do
    "${topdir}"/backup_recursive.sh ${submodule_org_repo} "${todaysdir}"
done

echo "Done with ${org_repo}!"

exit 0
