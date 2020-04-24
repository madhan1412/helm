#!/usr/bin/env bash

# Prerequisite
# Make sure you set secret enviroment variables in Travis CI
# DOCKER_USERNAME
# DOCKER_PASSWORD
# API_TOKEN

# set -ex

build() {

  echo "Found new version, building the image ${image}:${tag}"
  docker build --no-cache --build-arg VERSION=${tag} -t ${image}:${tag} .

  # run test
  version=$(docker run -ti --rm ${image}:${tag} version --client)
  #Client: &version.Version{SemVer:"v2.9.0-rc2", GitCommit:"08db2d0181f4ce394513c32ba1aee7ffc6bc3326", GitTreeState:"clean"}
  if [[ "${version}" == *"Error: unknown flag: --client"* ]]; then
    echo "Detected Helm3+"
    version=$(docker run -ti --rm ${image}:${tag} version)
    #version.BuildInfo{Version:"v3.0.0-beta.2", GitCommit:"26c7338408f8db593f93cd7c963ad56f67f662d4", GitTreeState:"clean", GoVersion:"go1.12.9"}
  fi
  version=$(echo ${version}| awk -F \" '{print $2}')
  if [ "${version}" == "v${tag}" ]; then
    echo "matched"
  else
    echo "unmatched"
    exit
  fi

  if [[ "$TRAVIS_BRANCH" == "master" ]]; then
    docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
    docker push ${image}:${tag}
  fi
}

image="alpine/helm"
repo="helm/helm"

# https://gist.github.com/mbohun/b161521b2440b9f08b59#file-githubapi-get-sh
GITHUB_API_HEADER_ACCEPT="Accept: application/vnd.github.v3+json"
echo $API_TOKEN
last_page=`curl -s -I "https://api.github.com/repos/${repo}/tags" -H "${GITHUB_API_HEADER_ACCEPT}" -H "Authorization: token ${API_TOKEN}" | grep '^Link:' | sed -e 's/^Link:.*page=//g' -e 's/>.*$//g'`

echo ${last_page}
for p in `seq 1 $last_page`; do
    tags=`curl -sL -H "Authorization: token ${API_TOKEN}" https://api.github.com/repos/${repo}/tags?page=$p |jq -r ".[].name"|sort -Vr|sed 's/^v//'`

    for tag in $tags
    do
      echo $tag
      status=$(curl -sL https://hub.docker.com/v2/repositories/${image}/tags/${tag})
      echo $status
      if [[ "${status}" =~ "not found" ]]; then
        build
      fi
    done
done

echo "Update latest image with latest release"
# output format for reference:
# <html><body>You are being <a href="https://github.com/helm/helm/releases/tag/v2.14.3">redirected</a>.</body></html>
latest=$(curl -s https://github.com/${repo}/releases)
latest=$(echo $latest\" |grep -oP '(?<=tag\/v)[0-9][^"-]*'|sort -Vr|head -1)
echo $latest

if [[ "$TRAVIS_BRANCH" == "master" && "$TRAVIS_PULL_REQUEST" == false ]]; then
  docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
  docker pull ${image}:${latest}
  docker tag ${image}:${latest} ${image}:latest
  docker push ${image}:latest
fi
