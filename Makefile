# Makefile

# Author: Sanjay <sanjay@alvyl.com>

.PHONY: install
install:
	npm install

.PHONY: build
build:
	- npm run build

.PHONY: start
start:
	- npm run start

.PHONY: test
test:
	- npm run test

.PHONY: lint
lint:
	- npm run lint

.PHONY: deploy
deploy:
	aws s3 sync --delete build "s3://${WEB_APP_S3_BUCKET}"
