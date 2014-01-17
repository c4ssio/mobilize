# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mobilize/version'

Gem::Specification.new do |spec|
  spec.name          = "mobilize"
  spec.version       = Mobilize::VERSION
  spec.authors       = ["Cassio Paes-Leme"]
  spec.email         = ["cassio.paesleme@gmail.com"]
  spec.description   = %q{Google Spreadsheets crontabs with AWS Redis/Resque cluster for execution}
  spec.summary       = %q{Google Spreadsheets crontabs with AWS Redis/Resque cluster for execution}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "bundler","1.5.2"
  spec.add_runtime_dependency "activesupport","3.2.15"
  spec.add_runtime_dependency "rake","10.1.0"
  spec.add_runtime_dependency "aws","2.4.5"
  spec.add_runtime_dependency "github_api","0.10.2"
  spec.add_runtime_dependency "gmail","0.4.0"
  spec.add_runtime_dependency "google_drive","0.3.6"
  spec.add_runtime_dependency "resque","1.25.1"
  spec.add_runtime_dependency "resque-pool","0.3.0"
  spec.add_runtime_dependency "god","0.13.3"
  spec.add_runtime_dependency "redis-objects"
  spec.add_runtime_dependency "mongoid", "3.1.4"
  spec.add_runtime_dependency "popen4","0.1.2"
  spec.add_runtime_dependency "pry","0.9.12.2"
  spec.add_runtime_dependency "pry-doc","0.4.6"
  spec.add_runtime_dependency "net-ssh","2.7.0"
  spec.add_runtime_dependency "net-scp","1.1.2"
  spec.add_runtime_dependency "settingslogic","2.0.9"
  spec.add_runtime_dependency "rake-hooks","1.2.3"
  spec.add_runtime_dependency "thread","0.1.1"
  spec.add_runtime_dependency "colorize","0.6.0"
  spec.add_runtime_dependency "m","1.3.2"
  spec.add_runtime_dependency "rack-protection","1.5.0"
  spec.add_runtime_dependency "trollop","1.16.2"
end
