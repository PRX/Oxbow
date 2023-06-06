# SHELL = /bin/sh

deploy-check: lint

lint: cfnlint prettier eslint typescript

cfnlint:
	cfn-lint --ignore-checks W --template template.yml

prettier:
	npm exec prettier -- --check "**/*.{js,json,yaml,yml}"

eslint:
	npm exec eslint -- "**/*.js"

typescript:
	npm exec tsc

bootstrap:
	npm install
	pip3 install -r requirements.txt
