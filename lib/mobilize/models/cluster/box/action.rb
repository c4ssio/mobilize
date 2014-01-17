module Mobilize
  class Box
    module Action
      def ssh
        _ssh_cmd                  = "ssh -i #{ Box.private_key_path } " +
                                    "-o 'UserKnownHostsFile=/dev/null' -o 'StrictHostKeyChecking=no' " +
                                    "#{ @box.user_name }@#{ @box.dns }"
        puts                        _ssh_cmd
      end

      def sh( _command,  _except = true, _streams = :stdout )
        _ssh_args                             = { keys: [ Box.private_key_path ],
                                                  paranoid: false }
        _command_file_path                    = "/tmp/" + "#{ _command }#{ Time.alphanunder_now }".to_md5
        @box.write                              _command, _command_file_path, false, false
        _send_args                            = [ @box.dns, @box.user_name, _ssh_args ]
        _attempter                            = Attempter.new Net::SSH, "start"
        _result                               = _attempter.attempt( *_send_args ) do |_ssh|
                                                  _ssh.run @box.name, "bash -l -c 'sh #{ _command_file_path }'",
                                                           _except, [ _streams ].flatten
                                                end

        _attempter.attempt( *_send_args ) { |_ssh| _ssh.run @box.name, "rm #{_command_file_path}" }

        if _streams == :stdout;_result[:stdout];else;_result;end
      end

      def cp( _loc_path, _rem_path = _loc_path, _mkdir = true, _log = true )
        @box.sh(                     "mkdir -p " + _rem_path.dirname ) if _mkdir
        _ssh_args                  = { keys: [ Box.private_key_path ],
                                       paranoid: false }
        _send_args                 = [ @box.dns, @box.user_name, _ssh_args ]
        _attempter                 = Attempter.new Net::SCP, "start"
        _result                    = _attempter.attempt( *_send_args ) do |_scp|
                                       _scp.upload!( _loc_path, _rem_path, recursive: true ) do |_ch, _name, _sent, _total|
                                       Log.write( "to #{ _name.basename } #{ _sent }/#{ _total }", "INFO", @box ) if _log
                                       end
                                     end
        _result
      end

      def write( _string, _rem_path, _mkdir = true, _log = true )
        _temp_file_path           = "/tmp/" + "#{ _string }#{ Time.alphanunder_now }".to_md5
        begin
          _temp_file_path.write     _string
          @box.cp                   _temp_file_path, _rem_path, _mkdir, false
        ensure
          _temp_file_path.rm_r
        end
        Log.write(                  "Wrote: #{ _string.ellipsize 25 } to #{ _rem_path }", "INFO", @box ) if _log
      end

      def write_mobrc
        _mobrc_path           = @box.mobilize_config_dir + "/mobrc"

        _mob_envs             = ENV.select { |_key, _value|
                                              _key.starts_with? "MOB" }

        _mobrc_string         = _mob_envs.map { |_key, _value|
                                              %{export #{ _key }=#{ _value }}
                                              }.join "\n"

        @box.write              _mobrc_string, _mobrc_path
        true
      end

      def terminate( _session = Box.session )
        #terminates the remote then
        #deletes the local database version
        if @box.remote_id
          _session.terminate_instances  @box.remote_id
          Log.write                     "Terminated remote #{ @box.remote_id }", "INFO", @box
        end

        @box.delete
        Log.write                       "Deleted from DB", "INFO", @box

        true
      end

      def launch( _session = Box.session )
        _remote_params               = { key_name:      @box.keypair_name,
                                         group_ids:     @box.security_groups,
                                         instance_type:   @box.size }

        _remotes                     = _session.launch_instances @box.ami, _remote_params
        _remote                      = _remotes.first

        @box.update_attributes         remote_id: _remote[ :aws_instance_id ]
        _session.create_tag            @box.remote_id, "Name", @box.name
        _remote                      = @box.wait_for_running _session
        @box                         = @box.sync _remote
        @box.wait_for_ssh
      end

      def wait_for_ssh
        while ( begin; @box.sh "hostname"; rescue; nil; end ).nil?
          Log.write                     "ssh not ready; waiting 10 sec", "INFO", @box
          sleep                         10
        end
        @box
      end

      def wait_for_running( _session  = Box.session )
        _remote                       = @box.remote _session
        while                           _remote[ :aws_state ] != "running"
          Log.write                     "remote still at #{ _remote[ :aws_state ] } -- waiting 10 sec", "INFO", @box
          sleep                         10
          _remote                     = @box.remote _session
        end
        _remote
      end

      def apt_install( _name, _version )
        Log.write                "Installing apt #{ _name } #{ _version }...", "INFO", @box
        @box.sh                  "sudo apt-get install -y #{ _name }=#{ _version }"
      end

      def install_ruby
        @box.sh           '\curl -L https://get.rvm.io | bash -s stable --ruby=1.9.3'
      end

      def install_gem_remote( _path = "c4ssio/mobilize" )
        @box.sh                         "rm -rf mobilize && " +
                                        "git clone http://u:p@github.com/#{ _path }.git --depth=1"
        _repo_revision                = @box.sh "cd mobilize && git log -1 --pretty=format:%H"
        _installed_revision           = begin; @box.sh "mob revision";rescue;nil;end
        if _installed_revision       != _repo_revision
          Log.write                     "Installing Mobilize\n" +
                                        "installed revision: #{ _installed_revision.to_s }\n" +
                                        "repo revision: #{ _repo_revision }", "INFO", @box
          @box.sh                       "cd mobilize && bundle install && rake install"
        else
           Log.write                    "mobilize revision #{ _installed_revision } already installed", "INFO", @box
        end
        @box.sh                         "rm -rf mobilize"
      end

      def install_gem_local
        _file_path = "pkg/#{ Dir.entries( "pkg" ).max }"
        @box.cp     _file_path
        @box.sh     "gem install -l #{ _file_path } --no-ri --no-rdoc"
      end

      def install_mobilize
        @box.install_ruby
        @box.install_git
        @box.install_redis

        @box.write_mobrc
        @box.write_keys

        @box.install_gem_remote
      end

      def write_keys
        @box.sh             "rm -f #{ @box.key_dir }/*", false
        ['box.ssh', 'git.ssh'].each do |_key|

          @box.cp           "#{ Config.key_dir }/#{ _key }",
                            "#{ @box.key_dir   }/#{ _key }"
        end
        @box.sh             "chmod 0600 #{ @box.key_dir }/*.ssh"
        @box.write_git_sh
        Log.write           "wrote and chmod'ed keys", "INFO", @box
      end

      def write_git_sh
        _git_ssh_path           = "#{ @box.key_dir }/git.ssh"

        #set git to not check strict host
        _git_sh_path           = "#{ @box.key_dir }/git.sh"

        _git_sh_cmd            = "#!/bin/sh\nexec /usr/bin/ssh " +
                                 "-o 'UserKnownHostsFile=/dev/null' -o 'StrictHostKeyChecking=no' " +
                                 "-i #{ _git_ssh_path } \"$@\""

        @box.write               _git_sh_cmd, _git_sh_path
        @box.sh                  "chmod 0700 #{ _git_sh_path }"

        return                    true
      end

      def install_git
        @box.apt_install               "git", "1:1.7.9.5-1"
      end

      def install_redis
        @box.apt_install                "redis-server", "2:2.2.12-1build1"
        #installation starts redis-server for some reason so stop it
        @box.sh                         "ps aux | grep redis-server | awk '{print $2}' | " +
                                        "(sudo xargs kill)", false
        true
      end
    end
  end
end
