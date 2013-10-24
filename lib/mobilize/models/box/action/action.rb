module Mobilize
  class Box
    module Action
      include Mobilize::Box::Action::Install
      include Mobilize::Box::Action::Write
      extend ActiveSupport::Concern
      included do
        field      :user_name,        type: String, default:->{Mobilize.config.box.user_name}
        field      :home_dir,         type: String, default:->{"/home/#{user_name}"}
      end

      def mobilize_home_dir;        "#{self.home_dir}/.mobilize";end

      def mobilize_config_dir;      "#{self.mobilize_home_dir}/config";end

      def key_dir;                  "#{self.mobilize_home_dir}/keys";end

      def view_ssh_cmd

        _box                      = self
        _ssh_cmd                  = "ssh -i #{Box.private_key_path} " +
                                    "-o 'UserKnownHostsFile=/dev/null' -o 'StrictHostKeyChecking=no' " +
                                    "#{_box.user_name}@#{_box.dns}"
        puts                        _ssh_cmd

      end

      def sh(_command,  _except = true, _streams = [:stdout, :stderr])

        _box                                  = self

        _ssh_args                             = {keys: [Box.private_key_path],
                                                 paranoid: false}
        _command_file_path                    = "/tmp/" + "#{_command}#{Time.now.utc.to_f.to_s}".to_md5

        _box.write                              _command, _command_file_path, false, false

        _send_args                             = ["start", _box.dns, _box.user_name, _ssh_args]

        _result                               = Net::SSH.send_w_retries(*_send_args) do |_ssh|
                                                  _ssh.run("bash -l -c 'sh #{_command_file_path}'", _except, _streams)
                                                end

        Net::SSH.send_w_retries(*_send_args)   {|_ssh| _ssh.run "rm #{_command_file_path}"}

        _result

      end

      def cp(_loc_path, _rem_path, _mkdir = true, _log = true)

        _box                       = self

        _box.sh(                     "mkdir -p " + File.dirname(_rem_path)) if _mkdir

        _ssh_args                  = {keys: [Box.private_key_path],
                                      paranoid: false}

        _send_args                 = ["start", _box.dns, _box.user_name, _ssh_args]

        _result                    = Net::SCP.send_w_retries(*_send_args) do |scp|
                                       scp.upload!(_loc_path, _rem_path, recursive: true) do |_ch, _name, _sent, _total|
                                         Logger.write("#{_name}: #{_sent}/#{_total}") if _log
                                       end
                                     end

        _result

      end

      def write(_string, _rem_path, _mkdir = true, _log = true)

        _box                      = self

        _temp_file_path           = "/tmp/" + "#{_string}#{Time.now.utc.to_f.to_s}".to_md5

        begin
          File.write                _temp_file_path, _string
          _box.cp                   _temp_file_path, _rem_path, _mkdir, false
        ensure
          FileUtils.rm              _temp_file_path, force: true
        end

        Logger.write                "Wrote: #{_string.ellipsize(25)} to #{_box.id}:#{_rem_path}" if _log

      end

      def start_engine

        _box                  = self

        _god_script_name      = "resque-pool-#{Mobilize.env}"

        _start_cmd            = "god && god load #{_box.mobilize_config_dir}/#{_god_script_name}.rb && " +
                                "god start #{_god_script_name}"

        _box.sh                 _start_cmd

        Logger.write            _start_cmd

        true

      end

      def stop_engine
        _box                  = self

        _box.sh                 "god stop resque-pool-#{Mobilize.env}"

        _pid_path             = "#{_box.mobilize_home_dir}/pid/resque-pool-#{Mobilize.env}.pid"

        _box.sh                 "kill -2 `cat #{_pid_path}`", false

      end
    end
  end
end
