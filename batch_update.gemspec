# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'batch_update'
  s.version     = '0.0.2'
  s.summary     = 'Update multiple records with different values in a small number of queries'
  s.description = 'A simple hello world gem'
  s.authors     = ['Quentin de Metz']
  s.email       = 'quentin@pennylane.com'
  s.files       = Dir['{lib}/**/*.rb']
  s.homepage    =
    'https://rubygems.org/gems/batch_update'
  s.license = 'MIT'

  s.required_ruby_version = '>= 3.3.4'

  s.add_dependency 'activerecord', '~> 7.0'
  s.add_dependency 'activesupport', '~> 7.0'

  s.metadata['rubygems_mfa_required'] = 'true'
end
