# SHELL = /bin/sh

deploy-check: lint

lint: cfnlint biome typescript standardrb

cfnlint:
	cfn-lint --ignore-checks W --template template.yml

typescript:
	npm exec tsc

biome:
	npm exec biome -- check

standardrb:
	bundle exec standardrb

bootstrap:
	bundle install
	npm install
	pip3 install -r requirements.txt
