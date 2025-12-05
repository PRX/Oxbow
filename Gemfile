# frozen_string_literal: true

source "https://rubygems.org"

# This should match the version that will exist in the CodeBuild environment
# defined in `oxbow-cd-pipeline.yml`, which is usually a new-ish patch of the
# selected minor version
ruby "3.2.9"

gem "aws-sdk-states", "~> 1"
gem "minitest"
gem "minitest-focus"
gem "minitest-reporters"
gem "rake"
gem "nokogiri"

group :development do
  gem "dotenv"
  gem "pry"
  gem "standard"
end
