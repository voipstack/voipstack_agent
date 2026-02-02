require 'yaml'
CRYSTAL_VERSION = '1.18'

PROJECTS = {
  agent: {
    binary_name: 'voipstack_agent',
    file_prefix: 'voipstack_agent_linux_x86_64'
  },
  media: {
    binary_name: 'voipstack_agent_media',
    file_prefix: 'voipstack_agent_media_linux_x86_64'
  }
}

# Métodos auxiliares
def get_version
  YAML.load(File.open('shard.yml'))['version']
end

def build_project(binary_name)
  shard_version = get_version
  git_rev = `git rev-parse --short HEAD`.chomp
  compile_time = Time.now.utc

  sh %(docker run -e COMPILE_SHARD_VERSION='#{shard_version}' -e COMPILE_TIME='#{compile_time}' -e COMPILE_GIT_REV='#{git_rev}' --rm -v .:/work -w /work crystallang/crystal:#{CRYSTAL_VERSION}-alpine /bin/sh -c 'shards install && shards build --production --static')

  binary_path = "./bin/#{binary_name}"
  raise 'expected static binary' unless `ldd #{binary_path} 2>&1`.chomp.include?('not a dynamic executable')
end

def compress_project(project)
  version = get_version
  file_name = "#{project[:file_prefix]}_#{version}.tar.gz"
  sh %(tar -czvf #{file_name} ./bin/#{project[:binary_name]})
  file_name
end

def create_to_github(version)
  raise 'GitHub CLI is not installed' unless system('command -v gh > /dev/null 2>&1')
  sh %(gh release create #{version} --latest --generate-notes --title "Release #{version}")
end

def upload_to_github(file_name, version)
  raise 'GitHub CLI is not installed' unless system('command -v gh > /dev/null 2>&1')
  sh %(gh release upload #{version} #{file_name})
end

# Tareas para voipstack_agent (originales - backward compatible)
desc 'Build production (voipstack_agent)'
task :prod do
  build_project(PROJECTS[:agent][:binary_name])
end

desc 'Compress and upload to GitHub release (voipstack_agent)'
task :upload_release do
  version = get_version
  file_name = compress_project(PROJECTS[:agent])
  upload_to_github(file_name, version)
end

# Tareas para voipstack_agent_media
namespace :prod do
  desc 'Build all projects'
  task all: [:prod]
end

namespace :upload_release do
  desc 'Compress and upload to GitHub release (voipstack_agent_media)'
  task :media do
    version = get_version
    file_name = compress_project(PROJECTS[:media])
    upload_to_github(file_name, version)
  end

  desc 'Upload all releases'
  task all: [:upload_release, :media]
end

# Tareas de conveniencia
namespace :release do
  desc 'Build and upload all releases'
  desc 'Create release'
  task :create do
    version = get_version
    create_to_github(version)
  end

  task all: ['prod:all', 'upload_release:all']
end
