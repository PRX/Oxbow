# SHELL = /bin/sh

deploy-check: lint

lint: cfnlint prettier eslint typescript

cfnlint:
	cfn-lint --ignore-checks W --template template.yml

prettier:
	npm run prettier -- --check "**/*.{js,json,yaml,yml}"

eslint:
	npm run eslint -- "**/*.js"

typescript:
	npm run tsc

bootstrap:
	npm install
	pip3 install -r requirements.txt
