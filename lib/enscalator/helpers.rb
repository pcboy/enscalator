require 'open3'
require 'ruby-progressbar'
require 'aws-sdk'

module Enscalator

  # Collection of helper classes and static methods
  module Helpers

    # Executed command as sub-processes with stdout and stderr streams
    #  taken from: https://nickcharlton.net/posts/ruby-subprocesses-with-stdout-stderr-streams.html
    class Subprocess

      # Create new subprocess and execute command there
      #
      # @param [String] cmd command to be executed
      def initialize(cmd)
        # standard input is not used
        Open3.popen3(cmd) do |_stdin, stdout, stderr, thread|
          {:out => stdout, :err => stderr}.each do |key, stream|
            Thread.new do
              until (line = stream.gets).nil? do
                # yield the block depending on the stream
                if key == :out
                  yield line, nil, thread if block_given?
                else
                  yield nil, line, thread if block_given?
                end
              end
            end
          end

          thread.join # wait for external process to finish
        end
      end
    end

    # Run command and print captured output to corresponding standard streams
    #
    # @param [Array] cmd command array to be executed
    # @return [String] produced output from executed command
    def run_cmd(cmd)
      # use contracts to get rid of exceptions: https://github.com/egonSchiele/contracts.ruby
      raise ArgumentError, "Expected Array, but actually was given #{cmd.class}" unless cmd.is_a?(Array)
      raise ArgumentError, 'Argument cannot be empty' if cmd.empty?
      command = cmd.join(' ')
      Subprocess.new command do |stdout, stderr, _thread|
        STDOUT.puts stdout if stdout
        STDERR.puts stderr if stderr
      end
    end

    # Cloudformation client
    #
    # @param [String] region Region in Amazon AWS
    # @return [Aws::CloudFormation::Client]
    # @raise [ArgumentError] when region is not given
    def cfn_client(region)
      raise ArgumentError,
            'Unable to proceed without region' if region.blank?
      Aws::CloudFormation::Client.new(region: region)
    end

    # Cloudformation resource
    #
    # @param [Aws::CloudFormation::Client] client instance of AWS Cloudformation client
    # @return [Aws::CloudFormation::Resource]
    # @raise [ArgumentError] when client is not provided or its not expected class type
    def cfn_resource(client)
      raise ArgumentError,
            'must be instance of Aws::CloudFormation::Client' unless client.instance_of?(Aws::CloudFormation::Client)
      Aws::CloudFormation::Resource.new(client: client)
    end

    # EC2 client
    #
    # @param [String] region Region in Amazon AWS
    # @return [Aws::EC2::Client]
    # @raise [ArgumentError] when region is not given
    def ec2_client(region)
      raise ArgumentError,
            'Unable to proceed without region' if region.blank?
      Aws::EC2::Client.new(region: region)
    end

    # Route 53 client
    #
    # @param [String] region AWS region identifier
    # @return [Aws::Route53::Client]
    # @raise [ArgumentError] when region is not given
    def route53_client(region)
      raise ArgumentError,
            'Unable to proceed without region' if region.blank?
      Aws::Route53::Client.new(region: region)
    end

    # Find ami images registered
    #
    # @param [Aws::EC2::Client] client instance of AWS EC2 client
    # @return [Hash] images satisfying query conditions
    # @raise [ArgumentError] when client is not provided or its not expected class type
    def find_ami(client, owners: ['self'], filters: nil)
      raise ArgumentError,
            'must be instance of Aws::EC2::Client' unless client.instance_of?(Aws::EC2::Client)
      query = {}
      query[:dry_run] = false
      query[:owners] = owners if owners.kind_of?(Array) && owners.any?
      query[:filters] = filters if filters.kind_of?(Array) && filters.any?
      client.describe_images(query)
    end

    # Wait until stack gets created
    #
    # @param [Aws::CloudFormation::Resource] cfn accessor for cloudformation resource
    # @param [String] stack_name name of the stack
    # @return [Aws::CloudFormation::Stack]
    def wait_stack(cfn, stack_name)

      stack = cfn.stack(stack_name)

      title = 'Waiting for stack to be created'
      progress = ProgressBar.create :title => title,
                                    :starting_at => 10,
                                    :total => nil

      loop do
        break unless stack.stack_status =~ /(CREATE|UPDATE)_IN_PROGRESS$/
        progress.title = title + " [#{stack.stack_status}]"
        progress.increment
        sleep 5
        stack = cfn.stack(stack_name)
      end

      stack
    end

    # Get resource for given key from given stack
    #
    # @param [Aws::CloudFormation::Stack] stack cloudformation stack instance
    # @param [String] key resource identifier (key)
    # @return [String] AWS resource identifier
    # @raise [ArgumentError] when stack is nil
    # @raise [ArgumentError] when key is nil or empty
    def get_resource(stack, key)
      raise ArgumentError, 'stack must not be nil' if stack.nil?
      raise ArgumentError, 'key must not be nil nor empty' if key.nil? || key.empty?

      # query with physical_resource_id
      resource = stack.resource(key).physical_resource_id rescue nil
      if resource.nil?
        # fallback to values from stack.outputs
        output = stack.outputs.select { |s| s.output_key == key }
        resource = output.first.output_value rescue nil
      end
      resource
    end

    # Get list of resources for given keys
    #
    # @param [Aws::CloudFormation::Stack] stack cloudformation stack instance
    # @param [Array] keys list of resource identifiers (keys)
    # @return [String] list of AWS resource identifiers
    # @raise [ArgumentError] when stack is nil
    # @raise [ArgumentError] when keys are nil or empty list
    def get_resources(stack, keys)
      raise ArgumentError, 'stack must not be nil' if stack.nil?
      raise ArgumentError, 'key must not be nil nor empty' if keys.nil? || keys.empty?

      keys.map { |k| get_resource(stack, k) }.compact
    end

    # Generate parameters list
    #
    # @param [Aws::CloudFormation::Stack] stack cloudformation stack instance
    # @param [Array] keys list of keys
    def generate_parameters(stack, keys)
      keys.map do |k|
        v = get_resource(stack, k)
        {:parameter_key => k, :parameter_value => v}
      end
    end


    # Call script
    #
    # @param [String] region AWS region identifier
    # @param [String] dependent_stack_name name of the stack current stack depends on
    # @param [String] script_path path to script
    # @param [Array] keys list of keys
    # @param [String] prepend_args prepend arguments
    # @param [String] append_args append arguments
    # @deprecated this method is no longer used
    def cfn_call_script(region,
                        dependent_stack_name,
                        script_path,
                        keys,
                        prepend_args: '',
                        append_args: '')

      cfn = cfn_resource(cfn_client(region))
      stack = wait_stack(cfn, dependent_stack_name)
      args = get_resources(stack, keys).join(' ')
      cmd = [script_path, prepend_args, args, append_args]

      begin
        run_cmd(cmd)
      rescue Errno::ENOENT
        puts $!.to_s
        STDERR.puts cmd
      end
    end

    # Create stack using cloudformation interface
    #
    # @param [String] region AWS region identifier
    # @param [String] dependent_stack_name name of the stack current stack depends on
    # @param [String] template name
    # @param [String] stack_name stack name
    # @param [Array] keys keys
    # @param [Array] extra_parameters additional parameters
    # @return [Aws::CloudFormation::Resource]
    # @deprecated this method is no longer used
    def cfn_create_stack(region,
                         dependent_stack_name,
                         template,
                         stack_name,
                         keys: [],
                         extra_parameters: [])

      cfn = cfn_resource(cfn_client(region))
      stack = wait_stack(cfn, dependent_stack_name)

      extra_parameters_cleaned = extra_parameters.map do |x|
        if x.has_key? 'ParameterKey'
          {:parameter_key => x['ParameterKey'], :parameter_value => x['ParameterValue']}
        else
          x
        end
      end

      options = {
        :stack_name => stack_name,
        :template_body => template,
        :parameters => generate_parameters(stack, keys) + extra_parameters_cleaned
      }

      cfn.create_stack(options)
    end

    # Create ssh public/private key pair, save private key for current user
    #
    # @param [String] key_name key name
    # @param [String] region aws region
    # @param [Boolean] force_create force to create a new ssh key
    def create_ssh_key(key_name, region, force_create: false)
      client = ec2_client(region)

      if !client.describe_key_pairs.key_pairs.collect(&:key_name).include?(key_name) || force_create
        # delete existed ssh key
        client.delete_key_pair(key_name: key_name)

        # create a new ssh key
        key_pair = client.create_key_pair(key_name: key_name)
        STDERR.puts "Created new ssh key with fingerprint: #{key_pair.key_fingerprint}"

        # save private key for current user
        private_key = File.join(ENV['HOME'], '.ssh', key_name)
        File.open(private_key, 'w') do |wfile|
          wfile.write(key_pair.key_material)
        end
        File.chmod(0600, private_key)
      else
        key_pair = Aws::EC2::KeyPair.new(key_name, client: client)
        STDERR.puts "Found existing ssh key with fingerprint: #{key_pair.key_fingerprint}"
      end
    end

    # Read user data from file
    #
    # @param [String] app_name application name
    def read_user_data(app_name)
      user_data_path = File.join(File.expand_path('..', __FILE__), 'confs', 'user-data', app_name)
      fail("User data path #{user_data_path} not exists") unless File.exist?(user_data_path)
      File.read(user_data_path)
    end
  end # module Asserts
end # module Enscalator
