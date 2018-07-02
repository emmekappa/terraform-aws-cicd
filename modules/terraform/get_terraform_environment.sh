#!/bin/sh
codebuild_regex='^codepipeline/.*-(.*)' # matching terraform-null-label module syntax and get the _stage_ part

if [[ $CODEBUILD_INITIATOR =~ $codebuild_regex ]]; then
	codebuild_environment="${BASH_REMATCH[1]}"
fi

if [[ $codebuild_environment == "master" ]]; then
    echo "production"
    exit 0
elif [[ $codebuild_environment == "develop" ]]; then
    echo "stage"
    exit 0
fi

if [[ $terraform_environment != "production" ]] && [[ $terraform_environment != "stage" ]]; then
    echo "SHOULD_SKIP"
    exit -1
fi

echo "SHOULD_NOT_BE_HERE"
exit -1