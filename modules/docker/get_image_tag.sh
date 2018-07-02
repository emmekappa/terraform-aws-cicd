#!/bin/sh

codebuild_regex='^codepipeline/.*-(.*)' # matching terraform-null-label module syntax and get the _stage_ part
if [[ $CODEBUILD_INITIATOR =~ $codebuild_regex ]]; then
	image_tag="${BASH_REMATCH[1]}"
elif [[ $CODEBUILD_SOURCE_VERSION == stage* ]]; then
	image_tag="stage"
elif [[ $CODEBUILD_SOURCE_VERSION == master* ]]; then
	image_tag="latest-codebuild"
elif [[ $CODEBUILD_SOURCE_VERSION == pr* ]]; then
	image_tag=$(echo $CODEBUILD_SOURCE_VERSION | sed -e 's/\//_/g')
else
	normalized_hash=$(echo $CODEBUILD_SOURCE_VERSION | sed -e 's/\//_/g')
	image_tag="commit_$normalized_hash"
fi

if [[ $image_tag == "master" ]]; then
	echo "latest"
else
	echo $image_tag
fi
