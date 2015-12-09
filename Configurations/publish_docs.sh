#!/bin/bash

# Change $TRAVIS_BRANCH check to `master` when we merge Switch 2 support
if [ "$TRAVIS_PULL_REQUEST" == "false" ] && [ "$TRAVIS_BRANCH" == "swift-2_0" ]; then
    echo -e "Generating Jazzy output \n"
    jazzy --swift-version 2.1 -m Deferred -g "https://github.com/bignerdranch/Deferred" -a "Big Nerd Ranch" -u "https://github.com/bignerdranch" --module-version=2.0.0 -r "http://bignerdranch.github.io/Deferred/"

    echo -e "Moving into docs directory \n"
    pushd docs

    echo -e "Creating gh-pages repo \n"
    git init
    git config user.email "travis@travis-ci.org"
    git config user.name "travis-ci"

    echo -e "Adding new docs \n"
    git add -A
    git commit -m "Publish docs from successful Travis build of $TRAVIS_COMMIT"
    git push --force --quiet "https://${GITHUB_ACCESS_TOKEN}@github.com/bignerdranch/Deferred" master:gh-pages > /dev/null 2>&1
    echo -e "Published latest docs.\n"

    echo -e "Moving out of docs clone and cleaning up"
    popd
fi