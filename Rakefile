require 'yaml'
CRYSTAL_VERSION = '1.17'

desc 'Build production'
task :prod do
  shard_config = YAML.load(File.open('shard.yml'))
  shard_version = shard_config['version']
  git_rev = `git rev-parse --short HEAD`.chomp
  compile_time = Time.now.utc

  sh %(docker run -e COMPILE_SHARD_VERSION='#{shard_version}' -e COMPILE_TIME='#{compile_time}' -e COMPILE_GIT_REV='#{git_rev}' --rm -v .:/work -w /work crystallang/crystal:#{CRYSTAL_VERSION}-alpine /bin/sh -c  'shards install && shards build --production --static')

  raise 'expected static binary' unless `ldd ./bin/voipstack_agent 2>&1`.chomp.include?('not a dynamic executable')
end

desc 'Compress and upload to GitHub release'
task :upload_release do
  version = YAML.load(File.open('shard.yml'))['version']
  file_name = "voipstack_agent_linux_x86_64_#{version}.tar.gz"

  sh %(tar -czvf #{file_name} ./bin/voipstack_agent)

  # Check if the GitHub CLI is installed
  raise 'GitHub CLI is not installed' unless system('command -v gh > /dev/null 2>&1')

  # Upload to GitHub release
  sh %(gh release create #{version} #{file_name} --latest --generate-notes --title "Release #{version}")
end
