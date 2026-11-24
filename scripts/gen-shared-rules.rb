#!/usr/bin/env ruby
# Writes KeepCore's bundled copy of the shared rules from contract/openapi.yaml.
# The app uses it only until the first answer of GET /v1/meta is cached.
#   ruby scripts/gen-shared-rules.rb          write the file
#   ruby scripts/gen-shared-rules.rb --check  fail when the file is out of date
require "yaml"
require "json"

root = File.expand_path("..", __dir__)
contract = YAML.load_file(File.join(root, "contract/openapi.yaml"))
out = File.join(root, "KeepCore/Sources/KeepCore/Resources/shared-rules.json")
text = JSON.pretty_generate(
  "contract_version" => contract["info"]["version"],
  "limits" => contract["x-limits"],
  "shared_rules" => contract["x-shared-rules"]
) + "\n"

if ARGV.include?("--check")
  abort("shared-rules.json is out of date: run ruby scripts/gen-shared-rules.rb") unless File.exist?(out) && File.read(out) == text
  puts "shared-rules.json is up to date"
else
  File.write(out, text)
  puts "wrote #{out}"
end
