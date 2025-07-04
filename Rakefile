require 'yaml'

desc "Build production"
task :prod do
  shard_config = YAML.load(File.open('shard.yml'))
  shard_version=shard_config['version']
  git_rev=%x[git rev-parse --short HEAD].chomp
  compile_time=Time.now.utc
  
  sh "shards install"
  sh "COMPILE_SHARD_VERSION='#{shard_version}' COMPILE_TIME='#{compile_time}' COMPILE_GIT_REV='#{git_rev}' shards build --production --static"
end
