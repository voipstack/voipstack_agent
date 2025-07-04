require 'yaml'
CRYSTAL_VERSION='1.16'

desc "Build production"
task :prod do
  shard_config = YAML.load(File.open('shard.yml'))
  shard_version=shard_config['version']
  git_rev=%x[git rev-parse --short HEAD].chomp
  compile_time=Time.now.utc
  
  sh %Q[docker run -e COMPILE_SHARD_VERSION='#{shard_version}' -e COMPILE_TIME='#{compile_time}' -e COMPILE_GIT_REV='#{git_rev}' --rm -v .:/work -w /work crystallang/crystal:#{CRYSTAL_VERSION}-alpine /bin/sh -c  'shards install && shards build --production --static']

  if not %x[ldd ./bin/voipstack_agent 2>&1].chomp.include?('not a dynamic executable')
    raise 'expected static binary'
  end
end
