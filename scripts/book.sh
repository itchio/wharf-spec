#!/bin/sh -xe

npm version
npm ci

npm run build

gsutil -m cp -r -a public-read _book/* gs://docs.itch.zone/wharf/$CI_BUILD_REF_NAME/
