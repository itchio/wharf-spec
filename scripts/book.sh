#!/bin/sh -xe

npm version
npm install -g gitbook-cli

gitbook build

gsutil cp -r -a public-read _book/* gs://docs.itch.ovh/wharf/$CI_BUILD_REF_NAME/
