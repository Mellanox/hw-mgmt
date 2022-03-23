#!/bin/bash

set -o pipefail

# fetch tags
git fetch --tags

# get current commit hash
commit=$(git rev-parse HEAD)
current_branch=$(git rev-parse --abbrev-ref HEAD)

new=$(version_tag.py -b $current_branch)
retVal=$?
echo "new tag:" $new
echo "Retcode: " $retVal
if [ $retVal -ne 0 ];
then
    echo "Failed to create new tag" $new
    exit $retVal
fi

# set outputs
echo ::set-output name=new_tag::$new

# create local git tag
git tag $new

# push new tag ref to github
dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
full_name=$GITHUB_REPOSITORY
git_refs_url=$(jq .repository.git_refs_url $GITHUB_EVENT_PATH | tr -d '"' | sed 's/{\/sha}//g')

echo "$dt: **pushing tag $new to repo $full_name"

git_refs_response=$(
curl -s -X POST $git_refs_url \
-H "Authorization: token $GITHUB_TOKEN" \
-d @- << EOF

{
  "ref": "refs/tags/$new",
  "sha": "$commit"
}
EOF
)

git_ref_posted=$( echo "${git_refs_response}" | jq .ref | tr -d '"' )

echo "::debug::${git_refs_response}"
if [ "${git_ref_posted}" = "refs/tags/${new}" ]; then
  exit 0
else
  echo "::error::Tag was not created properly."
  exit 1
fi
