#!/bin/env fish
git clean -fdx
chmod +x gradlew
cp -r ../Xed-Editor/local.properties .
./gradlew clean
./gradlew assembleRelease

