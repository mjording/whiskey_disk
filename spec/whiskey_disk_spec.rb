require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper.rb'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'whiskey_disk'))
require 'rake'

# WhiskeyDisk subclass that allows us to test in what order ssh commands are 
#   issued by WhiskeyDisk.run
class TestOrderedExecution < WhiskeyDisk
  class << self
    def commands
      result = @commands
      @commands = []
      result
    end
    
    def system(*args)
      @commands ||= []
      @commands << args.join(' ')
    end
  end
end

describe 'requiring the main library' do
  before do
    Rake.application = @rake = Rake::Application.new
    load File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'whiskey_disk', 'rake.rb'))
  end

  after do
    Rake.application = nil
  end

  it 'should make the deploy:setup rake task available' do
    Rake::Task.task_defined?('deploy:setup').should.be.true
  end

  it 'should make the deploy:now rake task available' do
    Rake::Task.task_defined?('deploy:now').should.be.true
  end
end

describe 'WhiskeyDisk' do
  describe 'determining if the deployment is remote' do
    before do
      @parameters = { 'deploy_to' => '/path/to/main/repo' }
      WhiskeyDisk.configuration = @parameters
    end
    
    it 'should work without arguments' do
      lambda { WhiskeyDisk.remote? }.should.not.raise(ArgumentError)
    end
    
    it 'should not allow arguments' do
      lambda { WhiskeyDisk.remote?(:foo) }.should.raise(ArgumentError)
    end
    
    it 'should return false if the configuration includes a nil domain setting' do
      @parameters['domain'] = nil
      WhiskeyDisk.remote?.should == false
    end

    it 'should return true if the configuration includes a non-empty domain setting' do
      @parameters['domain'] = [ { :name => 'smeghost' } ]
      WhiskeyDisk.remote?.should == true
    end
    
    it 'should return true if the configuration includes a multiple domain settings' do
      @parameters['domain'] = [ { :name => 'smeghost' }, { :name => 'faphost' } ]
      WhiskeyDisk.remote?.should == true
    end
  end
  
  describe 'determining if the deployment has a configuration repository' do
    before do
      @parameters = { 'deploy_to' => '/path/to/main/repo' }
      WhiskeyDisk.configuration = @parameters
    end
    
    it 'should work without arguments' do
      lambda { WhiskeyDisk.has_config_repo? }.should.not.raise(ArgumentError)
    end
    
    it 'should not allow arguments' do
      lambda { WhiskeyDisk.has_config_repo?(:foo) }.should.raise(ArgumentError)
    end
    
    it 'should return true if the configuration includes a non-empty config_repository setting' do
      @parameters['config_repository'] = 'git://foo.git'
      WhiskeyDisk.has_config_repo?.should == true
    end
    
    it 'should return false if the configuration includes a nil config_repository setting' do
      @parameters['config_repository'] = nil
      WhiskeyDisk.has_config_repo?.should == false
    end
    
    it 'should return false if the configuration includes a blank config_repository setting' do
      @parameters['config_repository'] = ''
      WhiskeyDisk.has_config_repo?.should == false
    end
  end
  
  describe 'enabling staleness checks' do
    it 'should ensure that staleness checks are activated' do
      WhiskeyDisk.reset
      WhiskeyDisk.enable_staleness_checks
      WhiskeyDisk.staleness_checks_enabled?.should == true      
    end
  end
  
  describe 'when checking staleness checks' do
    it 'should return false if staleness checks have not been enabled' do
      WhiskeyDisk.reset
      WhiskeyDisk.staleness_checks_enabled?.should == false
    end
    
    it 'should return true if staleness checks have been enabled' do
      WhiskeyDisk.reset
      WhiskeyDisk.enable_staleness_checks
      WhiskeyDisk.staleness_checks_enabled?.should == true
    end
  end

  describe 'ensuring that the parent path for the main repository checkout is present' do
    before do
      WhiskeyDisk.configuration = { 'deploy_to' => '/path/to/main/repo' }
    end
    
    it 'should fail if the deployment path is not specified' do
      WhiskeyDisk.configuration = {}
      lambda { WhiskeyDisk.ensure_main_parent_path_is_present }.should.raise
    end
    
    it 'should attempt to create the parent path for the repository' do
      WhiskeyDisk.ensure_main_parent_path_is_present
      WhiskeyDisk.buffer.last.should.match(%r{mkdir -p /path/to/main})
      WhiskeyDisk.buffer.last.should.not.match(%r{/path/to/main/repo})
    end
  end

  describe 'ensuring that the parent path for the configuration repository checkout is present' do
    before do
      WhiskeyDisk.configuration = { 'deploy_config_to' => '/path/to/config/repo' }
    end
    
    it 'should fail if the configuration deployment path is not specified' do
      WhiskeyDisk.configuration = {}
      lambda { WhiskeyDisk.ensure_config_parent_path_is_present }.should.raise
    end
    
    it 'should attempt to create the parent path for the repository' do
      WhiskeyDisk.ensure_config_parent_path_is_present
      WhiskeyDisk.buffer.last.should.match(%r{mkdir -p /path/to/config})
      WhiskeyDisk.buffer.last.should.not.match(%r{/path/to/config/repo})
    end
  end
  
  describe 'checking out the main repository' do
    before do
      @parameters = { 'deploy_to' => '/path/to/main/repo', 'repository' => 'git@ogtastic.com:whiskey_disk.git' }
      WhiskeyDisk.configuration = @parameters
    end
    
    it 'should fail if the deployment path is not specified' do
      WhiskeyDisk.configuration = @parameters.merge('deploy_to' => nil)
      lambda { WhiskeyDisk.checkout_main_repository }.should.raise
    end
    
    it 'should fail if the repository is not specified' do
      WhiskeyDisk.configuration = @parameters.merge('repository' => nil)
      lambda { WhiskeyDisk.checkout_main_repository }.should.raise
    end
    
    it 'should work from the main repository checkout parent path' do
      WhiskeyDisk.checkout_main_repository
      WhiskeyDisk.buffer.join(' ').should.match(%r{cd /path/to/main})
      WhiskeyDisk.buffer.join(' ').should.not.match(%r{cd /path/to/main/repo})
    end
      
    it 'should attempt to shallow clone the main repository to the repository checkout path' do
      WhiskeyDisk.checkout_main_repository
      WhiskeyDisk.buffer.join(' ').should.match(%r{clone --depth 1 #{@parameters['repository']} repo})
    end
    
    it 'should make the main repository clone conditional on the lack of a main repository checkout' do
      WhiskeyDisk.checkout_main_repository
      WhiskeyDisk.buffer.join(' ').should.match(%r{if \[ -e #{@parameters['deploy_to']} \]; then .*; fi})
    end
  end
  
  describe 'checking out the configuration repository' do
    before do
      @parameters = { 'deploy_config_to' => '/path/to/config/repo', 'config_repository' => 'git@ogtastic.com:config.git' }
      WhiskeyDisk.configuration = @parameters
    end

    it 'should fail if the configuration deployment path is not specified' do
      WhiskeyDisk.configuration = @parameters.merge('deploy_config_to' => nil)
      lambda { WhiskeyDisk.checkout_configuration_repository }.should.raise
    end

    it 'should fail if the configuration repository is not specified' do
      WhiskeyDisk.configuration = @parameters.merge('config_repository' => nil)
      lambda { WhiskeyDisk.checkout_configuration_repository }.should.raise
    end

    it 'should work from the configuration repository checkout parent path' do
      WhiskeyDisk.checkout_configuration_repository
      WhiskeyDisk.buffer.join(' ').should.match(%r{cd /path/to/config})
      WhiskeyDisk.buffer.join(' ').should.not.match(%r{cd /path/to/config/repo})
    end

    it 'should attempt to shallow clone the configuration repository to the repository checkout path' do
      WhiskeyDisk.checkout_configuration_repository
      WhiskeyDisk.buffer.join(' ').should.match(%r{clone --depth 1 #{@parameters['config_repository']} repo})
    end
    
    it 'should make the configuration repository clone conditional on the lack of a main repository checkout' do
      WhiskeyDisk.checkout_configuration_repository
      WhiskeyDisk.buffer.join(' ').should.match(%r{if \[ -e #{@parameters['deploy_config_to']} \]; then .*; fi})
    end
  end
  
  describe 'updating the main repository checkout' do
    before do
      @parameters = { 'deploy_to' => '/path/to/main/repo' }
      WhiskeyDisk.configuration = @parameters
    end
    
    it 'should fail if the deployment path is not specified' do
      WhiskeyDisk.configuration = @parameters.merge('deploy_to' => nil)
      lambda { WhiskeyDisk.update_main_repository_checkout }.should.raise
    end
    
    it 'should work from the main repository checkout path' do
      WhiskeyDisk.update_main_repository_checkout
      WhiskeyDisk.buffer.join(' ').should.match(%r{cd /path/to/main/repo})
    end
    
    it 'should attempt to fetch only the master branch from the origin if no branch is specified' do
      WhiskeyDisk.update_main_repository_checkout
      WhiskeyDisk.buffer.join(' ').should.match(%r{git fetch origin \+refs/heads/master:refs/remotes/origin/master})
    end
    
    it 'should attempt to fetch the specified branch from the origin if a branch is specified' do
      WhiskeyDisk.configuration = @parameters.merge({'branch' => 'production'})
      WhiskeyDisk.update_main_repository_checkout
      WhiskeyDisk.buffer.join(' ').should.match(%r{git fetch origin \+refs/heads/production:refs/remotes/origin/production})
    end

    it 'should attempt to reset the master branch from the origin if no branch is specified' do
      WhiskeyDisk.update_main_repository_checkout
      WhiskeyDisk.buffer.join(' ').should.match(%r{git reset --hard origin/master})
    end
    
    it 'should attempt to reset the specified branch from the origin if a branch is specified' do
      WhiskeyDisk.configuration = @parameters.merge({'branch' => 'production'})
      WhiskeyDisk.update_main_repository_checkout
      WhiskeyDisk.buffer.join(' ').should.match(%r{git reset --hard origin/production})
    end
  end
  
  describe 'updating the configuration repository checkout' do
    before do
      @parameters = { 'deploy_config_to' => '/path/to/config/repo' }
      WhiskeyDisk.configuration = @parameters
    end
    
    it 'should fail if the configuration deployment path is not specified' do
      WhiskeyDisk.configuration = @parameters.merge('deploy_config_to' => nil)
      lambda { WhiskeyDisk.update_configuration_repository_checkout }.should.raise
    end
    
    it 'should work from the main repository checkout path' do
      WhiskeyDisk.update_configuration_repository_checkout
      WhiskeyDisk.buffer.join(' ').should.match(%r{cd /path/to/config/repo})
    end
    
    it 'should attempt to fetch only the master branch from the origin if no configuration branch is specified' do
      WhiskeyDisk.update_configuration_repository_checkout
      WhiskeyDisk.buffer.join(' ').should.match(%r{git fetch origin \+refs/heads/master:refs/remotes/origin/master})
    end
    
    it 'should attempt to fetch the specified branch from the origin if a configuration branch is specified' do
      WhiskeyDisk.configuration = @parameters.merge({'config_branch' => 'production'})
      WhiskeyDisk.update_configuration_repository_checkout
      WhiskeyDisk.buffer.join(' ').should.match(%r{git fetch origin \+refs/heads/production:refs/remotes/origin/production})
    end
    
    it 'should attempt to reset the master branch from the origin if no configuration branch is specified' do
      WhiskeyDisk.update_configuration_repository_checkout
      WhiskeyDisk.buffer.join(' ').should.match(%r{git reset --hard origin/master})
    end

    it 'should attempt to reset the master branch from the origin if no configuration branch is specified' do
      WhiskeyDisk.configuration = @parameters.merge({'config_branch' => 'production'})
      WhiskeyDisk.update_configuration_repository_checkout
      WhiskeyDisk.buffer.join(' ').should.match(%r{git reset --hard origin/production})
    end
  end
  
  describe 'refreshing the configuration' do
    before do
      @parameters = { 'deploy_to' => '/path/to/main/repo', 
                      'deploy_config_to' => '/path/to/config/repo',
                      'environment' => 'production',
                      'config_repository' => 'git@git://foo.bar.git',
                      'config_branch' => 'master',
                      'config_target' => 'staging',
                      'project' => 'whiskey_disk' }
      WhiskeyDisk.configuration = @parameters
    end

    it 'should fail if the main deployment path is not specified' do
      WhiskeyDisk.configuration = @parameters.merge('deploy_to' => nil)
      lambda { WhiskeyDisk.refresh_configuration }.should.raise
    end
  
    it 'should fail if the configuration deployment path is not specified' do
      WhiskeyDisk.configuration = @parameters.merge('deploy_config_to' => nil)
      lambda { WhiskeyDisk.refresh_configuration }.should.raise
    end
  
    it 'should fail if no project name was specified' do
      WhiskeyDisk.configuration = @parameters.merge('project' => 'unnamed_project')
      lambda { WhiskeyDisk.refresh_configuration }.should.raise      
    end
  
    it 'should use rsync to overlay the configuration checkout for the project in the config target onto the main checkout' do
      WhiskeyDisk.refresh_configuration
      WhiskeyDisk.buffer.last.should.match(%r{rsync.* /path/to/config/repo/whiskey_disk/staging/ /path/to/main/repo/})
    end
  end

  describe 'running post setup hooks' do
    before do
      WhiskeyDisk.configuration = { 'deploy_to' => '/path/to/main/repo' }
    end
    
    it 'should fail if the deployment path is not specified' do
      WhiskeyDisk.configuration = {}
      lambda { WhiskeyDisk.run_post_setup_hooks }.should.raise
    end
    
    it 'should work from the main checkout directory' do
      WhiskeyDisk.run_post_setup_hooks
      WhiskeyDisk.buffer.join(' ').should.match(%r{cd /path/to/main/repo})
    end
    
    describe 'when a post setup script is specified' do
      describe 'and the script path does not start with a "/"' do      
        before do
          WhiskeyDisk.configuration = { 'deploy_to' => '/path/to/main/repo', 'post_setup_script' => '/path/to/setup/script' }
        end
      
        it 'should attempt to run the post setup script' do        
          WhiskeyDisk.run_post_setup_hooks
          WhiskeyDisk.buffer.join(' ').should.match(%r{sh -x .*/path/to/setup/script})
        end
      
        it 'should use an absolute path to run the post setup script when the script path starts with a "/"' do
          WhiskeyDisk.run_post_setup_hooks
          WhiskeyDisk.buffer.join(' ').should.match(%r{sh -x /path/to/setup/script})         
        end
        
        it 'should make the post setup script run conditional on the presence of the script' do
          WhiskeyDisk.run_post_setup_hooks
          WhiskeyDisk.buffer.join(' ').should.match(%r{if \[ -e /path/to/setup/script \]; then .*; fi})
        end
      end
      
      describe 'and the script path does not start with a "/"' do
        before do
          WhiskeyDisk.configuration = { 'deploy_to' => '/path/to/main/repo', 'post_setup_script' => 'path/to/setup/script' }
        end

        it 'should attempt to run the post setup script' do        
          WhiskeyDisk.run_post_setup_hooks
          WhiskeyDisk.buffer.join(' ').should.match(%r{sh -x .*/path/to/setup/script})
        end
      
        it 'should use a path relative to the setupment path to run the post setup script' do
          WhiskeyDisk.run_post_setup_hooks
          WhiskeyDisk.buffer.join(' ').should.match(%r{sh -x /path/to/main/repo/path/to/setup/script})
        end
        
        it 'should make the post setup script run conditional on the presence of the script' do
          WhiskeyDisk.run_post_setup_hooks
          WhiskeyDisk.buffer.join(' ').should.match(%r{if \[ -e /path/to/main/repo/path/to/setup/script \]; then .*; fi})
        end
      end
    end
        
    it 'should attempt to run the post setup rake tasks' do
      WhiskeyDisk.run_post_setup_hooks
      WhiskeyDisk.buffer.join(' ').should.match(%r{rake.*deploy:post_setup})
    end
    
    it 'should use the same environment when running the rake tasks' do
      WhiskeyDisk.run_post_setup_hooks
      WhiskeyDisk.buffer.join(' ').should.match(%r{to=#{@env}})      
    end
    
    it 'should make the post setup rake tasks conditional on the presence of a Rakefile in the deployment path' do      
      WhiskeyDisk.run_post_setup_hooks
      WhiskeyDisk.buffer.join(' ').should.match(%r{if \[ -e /path/to/main/repo/Rakefile \]; then .*; fi})
    end
    
    it 'should make the post setup rake tasks conditional on the deploy:post_setup rake task being defined' do
      WhiskeyDisk.run_post_setup_hooks
      WhiskeyDisk.buffer.join(' ').should.match(%r{if \[\[ \`rake -P | grep deploy:post_setup\` != "" \]\]; })      
    end

    it 'should ensure that any rake ENV variable are set when checking for deploy:post_setup tasks' do
      @parameters = { 'deploy_to' => '/path/to/main/repo', 'rake_env' => { 'RAILS_ENV' => 'production', 'FOO' => 'bar' } }
      WhiskeyDisk.configuration = @parameters
      WhiskeyDisk.run_post_setup_hooks
      @parameters['rake_env'].each_pair do |k,v|
        WhiskeyDisk.buffer.join(' ').should.match(%r{#{k}='#{v}' .*rake -P})
      end
    end
    
    it 'should set any rake_env variables when running the rake tasks' do
      @parameters = { 'deploy_to' => '/path/to/main/repo', 'rake_env' => { 'RAILS_ENV' => 'production', 'FOO' => 'bar' } }
      WhiskeyDisk.configuration = @parameters
      WhiskeyDisk.run_post_setup_hooks
      @parameters['rake_env'].each_pair do |k,v|
        WhiskeyDisk.buffer.join(' ').should.match(%r{#{k}='#{v}' })
      end
    end
  end
  
  describe 'running post deployment hooks' do
    before do
      WhiskeyDisk.configuration = { 'deploy_to' => '/path/to/main/repo' }
    end
    
    it 'should fail if the deployment path is not specified' do
      WhiskeyDisk.configuration = {}
      lambda { WhiskeyDisk.run_post_deploy_hooks }.should.raise
    end
    
    it 'should work from the main checkout directory' do
      WhiskeyDisk.run_post_deploy_hooks
      WhiskeyDisk.buffer.join(' ').should.match(%r{cd /path/to/main/repo})
    end
    
    describe 'when a post deployment script is specified' do
      describe 'and the script path does not start with a "/"' do      
        before do
          WhiskeyDisk.configuration = { 'deploy_to' => '/path/to/main/repo', 'post_deploy_script' => '/path/to/deployment/script' }
        end
      
        it 'should attempt to run the post deployment script' do        
          WhiskeyDisk.run_post_deploy_hooks
          WhiskeyDisk.buffer.join(' ').should.match(%r{sh -x .*/path/to/deployment/script})
        end
      
        it 'should use an absolute path to run the post deployment script when the script path starts with a "/"' do
          WhiskeyDisk.run_post_deploy_hooks
          WhiskeyDisk.buffer.join(' ').should.match(%r{sh -x /path/to/deployment/script})         
        end
        
        it 'should make the post deployment script run conditional on the presence of the script' do
          WhiskeyDisk.run_post_deploy_hooks
          WhiskeyDisk.buffer.join(' ').should.match(%r{if \[ -e /path/to/deployment/script \]; then .*; fi})
        end
      end
      
      describe 'and the script path does not start with a "/"' do
        before do
          WhiskeyDisk.configuration = { 'deploy_to' => '/path/to/main/repo', 'post_deploy_script' => 'path/to/deployment/script' }
        end

        it 'should attempt to run the post deployment script' do        
          WhiskeyDisk.run_post_deploy_hooks
          WhiskeyDisk.buffer.join(' ').should.match(%r{sh -x .*/path/to/deployment/script})
        end
      
        it 'should use a path relative to the deployment path to run the post deployment script' do
          WhiskeyDisk.run_post_deploy_hooks
          WhiskeyDisk.buffer.join(' ').should.match(%r{sh -x /path/to/main/repo/path/to/deployment/script})
        end
        
        it 'should make the post deployment script run conditional on the presence of the script' do
          WhiskeyDisk.run_post_deploy_hooks
          WhiskeyDisk.buffer.join(' ').should.match(%r{if \[ -e /path/to/main/repo/path/to/deployment/script \]; then .*; fi})
        end
      end
    end
        
    it 'should attempt to run the post deployment rake tasks' do
      WhiskeyDisk.run_post_deploy_hooks
      WhiskeyDisk.buffer.join(' ').should.match(%r{rake.*deploy:post_deploy})
    end
    
    it 'should use the same environment when running the rake tasks' do
      WhiskeyDisk.run_post_deploy_hooks
      WhiskeyDisk.buffer.join(' ').should.match(%r{to=#{@env}})      
    end

    it 'should make the post deployment rake tasks conditional on the presence of a Rakefile in the deployment path' do      
      WhiskeyDisk.run_post_deploy_hooks
      WhiskeyDisk.buffer.join(' ').should.match(%r{if \[ -e /path/to/main/repo/Rakefile \]; then .*; fi})
    end
    
    it 'should make the post deployment rake tasks conditional on the deploy:post_deploy rake task being defined' do
      WhiskeyDisk.run_post_deploy_hooks
      WhiskeyDisk.buffer.join(' ').should.match(%r{if \[\[ \`rake -P | grep deploy:post_deploy\` != "" \]\]; })      
    end

    it 'should ensure that any rake ENV variable are set when checking for deploy:post_setup tasks' do
      @parameters = { 'deploy_to' => '/path/to/main/repo', 'rake_env' => { 'RAILS_ENV' => 'production', 'FOO' => 'bar' } }
      WhiskeyDisk.configuration = @parameters
      WhiskeyDisk.run_post_deploy_hooks
      @parameters['rake_env'].each_pair do |k,v|
        WhiskeyDisk.buffer.join(' ').should.match(%r{#{k}='#{v}' .*rake -P})
      end
    end
    
    it 'should set any rake_env variables when running the rake tasks' do
      @parameters = { 'deploy_to' => '/path/to/main/repo', 'rake_env' => { 'RAILS_ENV' => 'production', 'FOO' => 'bar' } }
      WhiskeyDisk.configuration = @parameters
      WhiskeyDisk.run_post_deploy_hooks
      @parameters['rake_env'].each_pair do |k,v|
        WhiskeyDisk.buffer.join(' ').should.match(%r{#{k}='#{v}' })
      end
    end
  end
  
  describe 'flushing changes' do
    describe 'when running remotely' do
      before do
        WhiskeyDisk.configuration = { 'domain' => [ { :name => 'www.domain.com' } ], 'deploy_to' => '/path/to/main/repo' }
        WhiskeyDisk.stub!(:bundle).and_return('command string')
        WhiskeyDisk.stub!(:run)
      end
      
      it 'should bundle the buffer of commands' do
        WhiskeyDisk.enqueue('x')
        WhiskeyDisk.enqueue('y')
        WhiskeyDisk.should.receive(:bundle)
        WhiskeyDisk.flush
      end
      
      it 'should use "run" to run all the bundled commands at once' do
        WhiskeyDisk.should.receive(:run).with('command string')
        WhiskeyDisk.flush
      end
    end
    
    describe 'when running locally' do
      before do
        WhiskeyDisk.reset
        WhiskeyDisk.configuration = { 'deploy_to' => '/path/to/main/repo' }
        WhiskeyDisk.stub!(:bundle).and_return('command string')
        WhiskeyDisk.stub!(:system)
      end
      
      it 'should bundle the buffer of commands' do
        WhiskeyDisk.enqueue('x')
        WhiskeyDisk.enqueue('y')
        WhiskeyDisk.should.receive(:bundle).and_return('command string')
        WhiskeyDisk.flush
      end
      
      it 'should use "system" to run all the bundled commands at once' do
        WhiskeyDisk.should.receive(:system).with('command string')
        WhiskeyDisk.flush
      end
      
      it 'should record a failure result when the system command fails' do
        WhiskeyDisk.stub!(:system).and_return(false)
        WhiskeyDisk.flush
        WhiskeyDisk.results.should == [ { :domain => 'local', :status => false } ]
      end
      
      it 'should record a success result when the system command succeeds' do
        WhiskeyDisk.stub!(:system).and_return(true)
        WhiskeyDisk.flush
        WhiskeyDisk.results.should == [ { :domain => 'local', :status => true } ]
      end
    end
  end
  
  describe 'bundling up buffered commands for execution' do
    before do
      WhiskeyDisk.reset
    end
    
    describe 'when staleness checks are disabled' do
      it 'should return an empty string if there are no commands' do
        WhiskeyDisk.bundle.should == ''
      end

      it 'should wrap each command with {} and join with &&s' do
        WhiskeyDisk.enqueue("cd foo/bar/baz || true")
        WhiskeyDisk.enqueue("rsync -avz --progress /yer/mom /yo/")
        WhiskeyDisk.bundle.should == "{ cd foo/bar/baz || true ; } && { rsync -avz --progress /yer/mom /yo/ ; }"
      end

      it 'should not wrap the bundled commands inside a staleness check' do
        WhiskeyDisk.enqueue("cd foo/bar/baz || true")
        WhiskeyDisk.enqueue("rsync -avz --progress /yer/mom /yo/")
        WhiskeyDisk.bundle.should == "{ cd foo/bar/baz || true ; } && { rsync -avz --progress /yer/mom /yo/ ; }"
      end
    end

    describe 'when staleness checks are enabled' do
      before do
        WhiskeyDisk.enable_staleness_checks
      end
      
      describe 'but not we are not configured for staleness checks on this deployment' do
        before do
          ENV['check'] = nil
        end
        
        it 'should return an empty string if there are no commands' do
          WhiskeyDisk.bundle.should == ''
        end

        it 'should wrap each command with {} and join with &&s' do
          WhiskeyDisk.enqueue("cd foo/bar/baz || true")
          WhiskeyDisk.enqueue("rsync -avz --progress /yer/mom /yo/")
          WhiskeyDisk.bundle.should == "{ cd foo/bar/baz || true ; } && { rsync -avz --progress /yer/mom /yo/ ; }"
        end

        it 'should not wrap the bundled commands inside a staleness check' do
          WhiskeyDisk.enqueue("cd foo/bar/baz || true")
          WhiskeyDisk.enqueue("rsync -avz --progress /yer/mom /yo/")
          WhiskeyDisk.bundle.should == "{ cd foo/bar/baz || true ; } && { rsync -avz --progress /yer/mom /yo/ ; }"
        end       
      end
      
      describe 'and we are configured for staleness checks on this deployment' do
        before do
          ENV['check'] = 'true'
        end
        
        describe 'when no configuration repository is in use' do
          before do
            @deploy_to = '/path/to/main/repo'
            @repository = 'git@git://foo.bar.git'
            @parameters = { 'deploy_to' => @deploy_to, 'repository' => @repository }
            WhiskeyDisk.configuration = @parameters
            WhiskeyDisk.enable_staleness_checks
          end
          
          it 'should return an empty string if there are no commands' do
            WhiskeyDisk.bundle.should == ''
          end

          it 'should wrap each command with {} and join with &&s' do
            WhiskeyDisk.enqueue("cd foo/bar/baz || true")
            WhiskeyDisk.enqueue("rsync -avz --progress /yer/mom /yo/")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("{ cd foo/bar/baz || true ; } && { rsync -avz --progress /yer/mom /yo/ ; }")))
          end

          it 'should wrap the bundled commands inside a staleness check which checks only the main repo for staleness' do
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("if [[ $ml != ${mr%%\t*} ]] ; then { COMMAND ; }")))
          end
          
          it 'should add a notice message for when the repository is not stale' do
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("then { COMMAND ; }; else echo \"No changes to deploy.\"; fi")))            
          end
          
          it "should query the head of the main checkout's master branch if no branch is specified" do
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("cd #{@deploy_to}; ml=\`cat .git/refs/heads/master\`;")))
          end
          
          it "should query the head of the main checkout's specified branch if a branch is specified" do
            WhiskeyDisk.configuration = @parameters.merge({'branch' => 'production'})
            WhiskeyDisk.enable_staleness_checks
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("cd #{@deploy_to}; ml=\`cat .git/refs/heads/production\`;")))
          end
          
          it "should query the head on the main repository's master branch if no branch is specified" do            
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("mr=\`git ls-remote #{@repository} refs/heads/master\`;")))
          end
          
          it "should query the head of the main repository's specified branch if a branch is specified" do
            WhiskeyDisk.configuration = @parameters.merge({'branch' => 'production'})
            WhiskeyDisk.enable_staleness_checks
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("mr=\`git ls-remote #{@repository} refs/heads/production\`;")))
          end
          
          it 'should not check a configuration repository for staleness' do
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.not.match(/c[lr]=/)
          end
        end
      
        describe 'when a configuration repository is in use' do
          before do
            @deploy_to = '/path/to/main/repo'
            @repository = 'git@git://foo.bar.git'
            @deploy_config_to = '/path/to/config/repo'
            @config_repository = 'git@git://foo.bar-config.git'
            @parameters = { 
              'deploy_to' => @deploy_to, 'repository' => @repository,
              'deploy_config_to' => @deploy_config_to, 'config_repository' => @config_repository
            }
            WhiskeyDisk.configuration = @parameters
            WhiskeyDisk.enable_staleness_checks
          end
          
          it 'should return an empty string if there are no commands' do
            WhiskeyDisk.bundle.should == ''
          end

          it 'should wrap each command with {} and join with &&s' do
            WhiskeyDisk.enqueue("cd foo/bar/baz || true")
            WhiskeyDisk.enqueue("rsync -avz --progress /yer/mom /yo/")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("{ cd foo/bar/baz || true ; } && { rsync -avz --progress /yer/mom /yo/ ; }")))
          end

          it 'should wrap the bundled commands inside a staleness check which checks both main and config repos for staleness' do
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("if [[ $ml != ${mr%%\t*} ]] || [[ $cl != ${cr%%\t*} ]]; then { COMMAND ; }")))
          end
          
          it 'should add a notice message for when the repositories are not stale' do
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("then { COMMAND ; }; else echo \"No changes to deploy.\"; fi")))            
          end
          
          it "should query the head of the main checkout's master branch if no branch is specified" do
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("cd #{@deploy_to}; ml=\`cat .git/refs/heads/master\`;")))
          end
          
          it "should query the head of the main checkout's specified branch if a branch is specified" do
            WhiskeyDisk.configuration = @parameters.merge({'branch' => 'production'})
            WhiskeyDisk.enable_staleness_checks
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("cd #{@deploy_to}; ml=\`cat .git/refs/heads/production\`;")))
          end
          
          it "should query the head on the main repository's master branch if no branch is specified" do            
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("mr=\`git ls-remote #{@repository} refs/heads/master\`;")))
          end
          
          it "should query the head of the main repository's specified branch if a branch is specified" do
            WhiskeyDisk.configuration = @parameters.merge({'branch' => 'production'})
            WhiskeyDisk.enable_staleness_checks
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("mr=\`git ls-remote #{@repository} refs/heads/production\`;")))
          end
          
          it "should query the head of the config checkout's master branch if no branch is specified" do
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("cd #{@deploy_config_to}; cl=\`cat .git/refs/heads/master\`;")))
          end
          
          it "should query the head of the config checkout's specified branch if a branch is specified" do
            WhiskeyDisk.configuration = @parameters.merge({'config_branch' => 'production'})
            WhiskeyDisk.enable_staleness_checks
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("cd #{@deploy_config_to}; cl=\`cat .git/refs/heads/production\`;")))
          end
          
          it "should query the head on the config repository's master branch if no branch is specified" do            
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("cr=\`git ls-remote #{@config_repository} refs/heads/master\`;")))
          end
          
          it "should query the head of the config repository's specified branch if a branch is specified" do
            WhiskeyDisk.configuration = @parameters.merge({'config_branch' => 'production'})
            WhiskeyDisk.enable_staleness_checks
            WhiskeyDisk.enqueue("COMMAND")
            WhiskeyDisk.bundle.should.match(Regexp.new(Regexp.escape("cr=\`git ls-remote #{@config_repository} refs/heads/production\`;")))
          end
        end
      end
    end
  end
  
  describe 'when running a command string remotely' do
    before do
      WhiskeyDisk.reset
      @domain = 'ogc@ogtastic.com'
      WhiskeyDisk.configuration = { 'domain' => [ { :name => @domain } ] }
      WhiskeyDisk.stub!(:system)      
    end
    
    it 'should accept a command string' do
      lambda { WhiskeyDisk.run('ls') }.should.not.raise(ArgumentError)
    end
    
    it 'should require a command string' do
      lambda { WhiskeyDisk.run }.should.raise(ArgumentError)
    end
    
    it 'should fail if the domain path is not specified' do
      WhiskeyDisk.configuration = {}
      lambda { WhiskeyDisk.run('ls') }.should.raise
    end

    describe 'and a single domain is specified' do
      before do
        @domain = 'ogc@ogtastic.com'
        WhiskeyDisk.configuration = { 'domain' => [ { :name => @domain } ] }
      end
      
      it 'should pass the string to ssh with verbosity enabled' do
        WhiskeyDisk.should.receive(:system).with('ssh', '-v', @domain, "set -x; ls")
        WhiskeyDisk.run('ls')
      end
      
      it 'should include domain role settings when the domain has roles' do
        WhiskeyDisk.configuration = { 'domain' => [ { :name => @domain, :roles => [ 'web', 'db' ] } ] }
        WhiskeyDisk.should.receive(:system).with('ssh', '-v', @domain, "set -x; export WD_ROLES='web:db'; ls")
        WhiskeyDisk.run('ls')        
      end
    end
    
    describe 'and multiple domains are specified' do
      before do
        @domains = [ { :name => 'ogc@ogtastic.com' }, { :name => 'foo@example.com' } ]
      end
            
      it 'should run the command via ssh on each domain in the order specified in the configuration file' do
        TestOrderedExecution.configuration = { 'domain' => @domains }
        TestOrderedExecution.run('ls')
        TestOrderedExecution.commands.should == [
          "ssh -v ogc@ogtastic.com set -x; ls", 
          "ssh -v foo@example.com set -x; ls"
        ]
      end
      
      it 'should include role settings for each domain when available' do
        @domains = [ 
          { :name => 'ogc@ogtastic.com', :roles => [ 'db', 'web' ] }, 
          { :name => 'foo@example.com', :roles => [ 'app' ] } 
        ]
        TestOrderedExecution.configuration = { 'domain' => @domains }
        TestOrderedExecution.run('ls')
        TestOrderedExecution.commands.should == [
          "ssh -v ogc@ogtastic.com set -x; export WD_ROLES='db:web'; ls", 
          "ssh -v foo@example.com set -x; export WD_ROLES='app'; ls"
        ]
      end
      
      it 'should not fail if an ssh command fails' do
        WhiskeyDisk.configuration = { 'domain' => @domains }
        WhiskeyDisk.stub!(:system).with('ssh', '-v', 'ogc@ogtastic.com', 'set -x; ls').and_return(false)
        lambda { WhiskeyDisk.run('ls') }.should.not.raise(RuntimeError)
      end
      
      it 'should continue to run the remaining ssh commands when an ssh fails' do
        WhiskeyDisk.configuration = { 'domain' => @domains }
        WhiskeyDisk.stub!(:system).with('ssh', '-v', 'ogc@ogtastic.com', 'set -x; ls').and_return(false)
        WhiskeyDisk.should.receive(:system).with('ssh', '-v', 'foo@example.com', 'set -x; ls')
        WhiskeyDisk.run('ls')   
      end
      
      it 'should record failure and success status for issued ssh commands' do
        WhiskeyDisk.configuration = { 'domain' => @domains }
        WhiskeyDisk.stub!(:system).with('ssh', '-v', 'ogc@ogtastic.com', 'set -x; ls').and_return(false)
        WhiskeyDisk.stub!(:system).with('ssh', '-v', 'foo@example.com', 'set -x; ls').and_return(true)
        WhiskeyDisk.run('ls')   
        WhiskeyDisk.results.should == [ { :domain => 'ogc@ogtastic.com', :status => false }, 
                                        { :domain => 'foo@example.com', :status => true} ]
      end
    end
  end
  
  describe 'determining if all the deployments succeeded' do
    before do
      WhiskeyDisk.reset
    end
    
    it 'should work without arguments' do
      lambda { WhiskeyDisk.success? }.should.not.raise(ArgumentError)
    end
    
    it 'should not allow arguments' do
      lambda { WhiskeyDisk.success?(:foo) }.should.raise(ArgumentError)
    end
    
    it 'should return true if there are no results recorded' do
      WhiskeyDisk.success?.should.be.true
    end
    
    it 'should return true if all recorded results have true statuses' do
      WhiskeyDisk.record_result('1', true)
      WhiskeyDisk.record_result('2', true)
      WhiskeyDisk.record_result('3', true)
      WhiskeyDisk.success?.should.be.true
    end
    
    it 'should return false if any recorded result has a false status' do
      WhiskeyDisk.record_result('1', true)
      WhiskeyDisk.record_result('2', false)
      WhiskeyDisk.record_result('3', true)
      WhiskeyDisk.success?.should.be.false      
    end
  end
  
  describe 'summarizing the results of a run' do
    before do
      WhiskeyDisk.reset
      WhiskeyDisk.stub!(:puts)
    end
    
    it 'should work without arguments' do
      lambda { WhiskeyDisk.summarize }.should.not.raise(ArgumentError)
    end
    
    it 'should not allow arguments' do
      lambda { WhiskeyDisk.summarize(:foo) }.should.raise(ArgumentError)      
    end
    
    it 'should output a no runs message when no results are recorded' do
      WhiskeyDisk.should.receive(:puts).with('No deployments to report.')
      WhiskeyDisk.summarize
    end
    
    describe 'and there are results recorded' do
      before do
        WhiskeyDisk.record_result('foo@bar.com', false)
        WhiskeyDisk.record_result('ogc@ogtastic.com', true)
        WhiskeyDisk.record_result('user@example.com', true)
      end
      
      it 'should output a status line for each recorded deployment run' do
        WhiskeyDisk.should.receive(:puts).with('foo@bar.com => failed.')
        WhiskeyDisk.should.receive(:puts).with('ogc@ogtastic.com => succeeded.')
        WhiskeyDisk.should.receive(:puts).with('user@example.com => succeeded.')
        WhiskeyDisk.summarize
      end
    
      it 'should output a summary line including the total runs, count of failures and count of successes.' do
        WhiskeyDisk.should.receive(:puts).with('Total: 3 deployments, 2 successes, 1 failure.')        
        WhiskeyDisk.summarize
      end
    end
  end
end
