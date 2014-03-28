Gem::Specification.new do |s|
  s.name = 'vcs-ann'
  s.version = '0.1'
  s.licenses = ['BSD-3-Clause']
  s.date = '2014-04-29'
  s.author = 'Tanaka Akira'
  s.email = 'akr@fsij.org'
  s.required_ruby_version = '>= 2.1'
  s.files = %w[
    LICENSE
    README.md
    bin/vcs-ann
    lib/vcs-ann.rb
    lib/vcs-ann/git.rb
    lib/vcs-ann/main.rb
    lib/vcs-ann/svn.rb
  ]
  s.test_files = %w[
  ]
  s.homepage = 'https://github.com/akr/vcs-ann'
  s.require_path = 'lib'
  s.executables << 'vcs-ann'
  s.summary = 'an interactive wrapper for "annotate" and "diff" of svn and git'
  s.description = <<'End'
vcs-ann is an interactive wrapper for "annotate" and "diff" of svn and git.

vcs-ann enables you to browse annotated sources and diffs interactively.
End
end
