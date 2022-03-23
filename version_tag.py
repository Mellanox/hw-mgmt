#!/usr/bin/env python

import sys
import os
import json
import argparse
import subprocess
import re
import pdb

#parser = argparse.ArgumentParser(description='hw-management version tag')
#parser.add_argument('-b', '--param', dest='param', help='Set parameters. Example:\n-p MLNX_HW_MANAGEMENT_VERSION V.7.0020.2000_BR, KERNEL_UPDATE_PATCHES n', nargs='+', action='append')
#args = parser.parse_args()

def shell_cmd(command):
    subp = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE)
    out,err = subp.communicate()
    return out

pdb.set_trace()
# 1. get branch name before latest
branch = shell_cmd('git branch -r | grep -E ".*origin/V.7.[0-9]+.[0-9]+_BR$"').splitlines()[-2]
if len(branch) <= 5:
    sys.exit(1)

# get tag substring from branch
result = re.match(r'.*origin/(V.7.\d+.[0-9][0-9])[0-9][0-9]_BR', branch)
if result is None:
    tag_branch=branch
else:
    tag_branch =result.group(1)

# get all tags
all_tags_list = shell_cmd("git tag --list --merged HEAD --sort=-v:refname").splitlines()

# get last tag
r = re.compile(tag_branch + "[0-9]{2}$")
tag_branch_list = list(filter(r.match, all_tags_list))

tag_branch_list.sort()
if len(tag_branch_list) >= 1:
    last_tag = tag_branch_list[-1]

    # Incrament last tag
    last_tag_idx = last_tag[-2:]
    new_tag_idx = int(last_tag_idx) + 1
else:
    new_tag_idx = 30

new_tag = "{}{}".format(tag_branch, new_tag_idx)
print(new_tag)
sys.exit(0)

