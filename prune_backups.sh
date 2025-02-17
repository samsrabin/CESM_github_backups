#!/bin/bash
set -e

# Delete any files more than 2 weeks old, unless there's only one left

backups=(CESM_repos*tgz)
if [[ ${#backups[@]} -gt 1 ]]; then
   find . -maxdepth 1 -mtime +14 -name "CESM_repos*tgz" -delete 
fi

exit 0
