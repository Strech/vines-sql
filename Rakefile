require 'rake'
require 'rake/clean'
require 'rake/testtask'

CLOBBER.include('pkg')

directory 'pkg'

desc 'Build distributable packages'
task :build => [:pkg] do
  system 'gem build vines-sql.gemspec && mv vines-*.gem pkg/'
end

Rake::TestTask.new(:test) do |test|
  test.libs << 'spec'
  test.pattern = 'spec/**/*_spec.rb'
  test.warning = false
end

desc 'Create migration file'
task :generate_migration, :file_name do |_, options|
  require 'active_record'

  migrations_path = File.expand_path('../lib/vines/storage/db/migrations', __FILE__)
  migration_name = "#{Time.now.utc.strftime('%Y%m%d%H%M%S')}_#{options[:file_name]}.rb"

  puts "Creating file \e[32m#{migration_name}\e[0m"
  FileUtils.touch File.join(migrations_path, migration_name)
end

task :default => [:clobber, :test, :build]
