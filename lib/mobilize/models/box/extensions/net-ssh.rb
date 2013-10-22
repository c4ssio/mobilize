#use run after opening a session to
#get a proper reading of stderr, exit code, exit signal
#adapted from http://stackoverflow.com/questions/3386233/how-to-get-exit-status-with-rubys-netssh-library
module Net
  module SSH
    module Connection
      class Session
        #except=true means exception will be raised on exit_code != 0
        def run(command, except=true, streams = [ :stdout, :stderr ])

          _ssh, @stdout_data, @stderr_data    = self, "", ""
          @exit_code, @exit_signal, @streams  = nil, nil, streams

          @command, _except                   = command, except

          _ssh.open_channel                 do |channel|
            _ssh.run_proc(channel)
          end
          _ssh.loop

          if                                    _except and @exit_code!=0
            Mobilize::Logger.write              @stderr_data, "FATAL"
          else
            _result                           = {  stdout:      @stdout_data,
                                                   stderr:      @stderr_data,
                                                   exit_code:   @exit_code,
                                                   exit_signal: @exit_signal  }
            _result
          end
        end
        def run_proc(channel)
          @ssh                     = self
          channel.exec(@command) do |ch, success|
            unless                            success
              Mobilize::Logger.write          "FAILED: couldn't execute command (ssh.channel.exec)", "FATAL"
            end
            channel.on_data                   do |ch_d,data|
              @stdout_data                    += data
              @ssh.log_stream                    :stdout, data
            end

            channel.on_extended_data          do |ch_ed,type,data|
              @stderr_data                    += data
              @ssh.log_stream                    :stderr, data
            end

            channel.on_request("exit-status") do |ch_exst,data|
              @exit_code                       = data.read_long
            end

            channel.on_request("exit-signal") do |ch_exsig, data|
              @exit_signal                     = data.read_long
            end
          end
        end
        def log_stream(stream,data)
          Mobilize::Logger.write("#{stream.to_s}: #{data}")  if @streams.include?(stream)
        end
      end
    end
  end
end