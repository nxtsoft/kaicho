# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kaicho/version'

Gem::Specification.new do |spec|
  spec.name          = 'kaicho'
  spec.version       = Kaicho::VERSION
  spec.authors       = ['Stone Tickle']
  spec.email         = ['lattis@mochiro.moe']

  spec.summary       = 'a resource manager'
  spec.homepage      = 'https://github.com/annacrombie/kaicho'

  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{^(test|spec|features)/})
    end
  end

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler',   '~> 1.16', '>=1.16.5'
  spec.add_development_dependency 'rake',      '~> 12.3', '>=12.3.1'
  spec.add_development_dependency 'rspec',     '~> 3.8',  '>=3.8.0'
  spec.add_development_dependency 'coveralls', '~> 0.8',  '>=0.8.22'
end
