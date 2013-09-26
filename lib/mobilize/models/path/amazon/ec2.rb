module Mobilize
  #an Ec2 resolves to an ec2 instance
  class Ec2 < Path
    include Mongoid::Document
    include Mongoid::Timestamps
    field :name, type: String #name tag on the ec2 instance
    field :ami, type: String, default:->{@@config.ami}
    field :size, type: String, default:->{@@config.size}
    field :keypair_name, type: String, default:->{@@config.keypair_name}
    field :security_groups, type: Array, default:->{@@config.security_groups}
    field :instance_id, type: String
    field :dns, type: String #public dns
    field :ip, type: String #private ip
    field :_id, type: String, default:->{ "#{self.to_s.downcase}::#{name}" }

    index({dns: 1}, {unique: true, name: "dns_index"})

    @@config = Mobilize.config.ec2

    def cache(task)
      return "#{@@config.cache}/#{self.user.ssh_name}/#{task.job.name}"
    end

    def create_cache(task)
      @ec2 = self
      @task = task
      #clear out and regenerate server folder
      @ec2.ssh("mkdir -p #{@ec2.cache(@task)}")
      Logger.info("Created cache for #{@task.id}")
      return true
    end

    def clear_cache(task)
      @ec2 = self
      @task = task
      @ec2.purge_cache(@task)
      @ec2.create_cache(@task)
      Logger.info("Cleared cache for #{@task.id}")
    end

    def purge_cache(task)
      @job = self
      @job.ssh("sudo rm -rf #{@job.server_cache}*")
      Logger.info("Removed #{@job.server_cache}*")
    end

    def Ec2.session(access_key_id=Mobilize.config.aws.access_key_id,
                      secret_access_key=Mobilize.config.aws.secret_access_key,
                      region=@@config.region)
      @session = Aws::Ec2.new(access_key_id,secret_access_key,region: region)
      Logger.info("Logged into ec2 for region #{region}")
      return @session
    end

    def Ec2.instances(session, params={aws_state: ['running','pending']})
      @session = session
      all_insts = @session.describe_instances.map{|i| i.with_indifferent_access}
      filtered_insts = Ec2.filter_instances(all_insts,params)
      Logger.info("got #{filtered_insts.length.to_s} instances for #{@session.params[:region]}, params: #{params.to_s}")
      return filtered_insts
    end

    def Ec2.filter_instances(all_insts,params={aws_state: ['running','pending']})
      all_insts.select do |i|
        match_array = params.map{|k,v| v.to_a.include?(i[k])}.uniq
        match_array.length == 1 and match_array.first == true
      end
    end

    def Ec2.instances_by_name(name,session,params={aws_state: ['running','pending']})
      @session = session
      insts = Ec2.instances(@session).select{|i| i[:tags][:name] == name}
      Logger.info("found #{insts.length.to_s} instances by name #{name}")
      return insts
    end


    def find_or_create_instance(session)
      @ec2 = self
      @session = session
      begin
        #check for an instance_id assigned, so verify and
        #update w any changes
        return @ec2.instance(@session) if @ec2.instance_id
      rescue
        #go ahead and create an instance if it turns out this ID is wrong
      end
      #create an instance based on current parameters
      return @ec2.create_instance(@session)
    end

    #find instance by ID, update DB record with latest from AWS
    def instance(session)
      @ec2 = self
      @session = session
      inst = Ec2.instances(@session,
               {aws_instance_id: @ec2.instance_id,
                aws_state: ['running','pending']}).first
      inst = @ec2.create_instance(@session) if inst.nil?
      @ec2.sync(inst)
      return inst
    end

    def sync(rem_inst)
      @ec2 = self
      @ec2.update_attributes(
        ami: rem_inst[:aws_image_id],
        size: rem_inst[:instance_type],
        keypair_name: rem_inst[:keypair_name],
        security_groups: rem_inst[:group_ids],
        instance_id: rem_inst[:aws_instance_id],
        dns: rem_inst[:dns_name],
        ip: rem_inst[:aws_private_ip_address]
      )
      Logger.info("synced instance #{@ec2.instance_id} with remote.")
      return @ec2
    end

    def purge!(session)
      #terminates the remote instance then
      #deletes the local database instance
      @ec2 = self
      @session = session
      #terminate instances by name
      insts = Ec2.instances_by_name(@ec2.name,@session)
      insts.each do |i|
        @session.terminate_instances([i[:aws_instance_id]])
        Logger.info("Terminated instance #{i[:aws_instance_id]}")
      end
      @ec2.delete
      Logger.info("Purged #{@ec2.id} from DB")
      return true
    end

    def launch(session)
      @ec2 = self
      @session = session
      inst_params = {key_name: @ec2.keypair_name, group_ids: @ec2.security_groups, instance_type: @ec2.size}
      inst = @session.launch_instances(@ec2.ami, inst_params).first
      @session.create_tag(inst[:aws_instance_id],"name", @ec2.name)
      return inst
    end

    def resolve_instance(session)
      @ec2 = self
      @session = session
      insts = Ec2.instances_by_name(@ec2.name,@session)
      if insts.length>1
        Logger.error("You have more than 1 running instance named #{@ec2.name} -- please investigate your configuration")
      elsif insts.length == 1
        inst = insts.first
        Logger.info("Instance #{inst[:aws_instance_id]} found, assigning to #{@ec2.name}")
      elsif insts.empty?
        inst = nil
      end
      return inst
    end

    def wait_for_instance(session)
      @ec2 = self
      @session = session
      while (state=@ec2.instance(@session)[:aws_state]) != "running"
        Logger.info("Instance #{@ec2.instance_id} still at #{state} -- waiting 10 sec")
        sleep 10
      end
    end

    def create_instance(session)
      @ec2 = self
      @session = session
      inst = @ec2.resolve_instance(@session) || @ec2.launch(@session)
      @ec2.sync(inst)
      #wait around until the instance is running
      @ec2.wait_for_instance(@session)
      return @ec2.instance(@session)
    end

    def run(session,job)
      @session = session
      @job = job
      @job.clear_server
      #job worker directory to server
      @job.commit
      @job.purge_worker
      begin
        exec_cmd = "(cd #{@job.server_cache} && sh stdin) > " +
                   "#{@job.server_cache}/stdout 2> " +
                   "#{@job.server_cache}/stderr"
        @job.ssh(exec_cmd)
        Logger.info("Completed job for #{@job.id}")
      rescue
        Logger.error("Failed job #{@job.id} with #{@job.stderr}")
      end
      return @job.stdout      
    end
   
    def ssh(command,except=true)
      @ec2 = self
      ssh_args = {keys: @@config.private_key_path,paranoid: false}
      @result = Net::SSH.send_w_retries("start",@ec2.dns,@@config.root_user,ssh_args) do |ssh|
        ssh.run(command,except)
      end
      return @result
    end

    def scp(loc_path, rem_path)
      @ec2 = self
      ssh_args = {keys: @@config.private_key_path,paranoid: false}
      @result = Net::SCP.send_w_retries("start",@ec2.dns,@@config.root_user,ssh_args) do |scp|
        scp.upload!(loc_path,rem_path) do |ch, name, sent, total|
          Logger.info("#{name}: #{sent}/#{total}")
        end
      end
      return @result
    end
  end
end
