# -*- encoding : utf-8 -*-

require 'open3'
require 'ruby-progressbar'

module Enscalator

  # Collection of helper classes and static methods
  module Helpers

    # Executed command as sub-processes with stdout and stderr streams
    #  taken from: https://nickcharlton.net/posts/ruby-subprocesses-with-stdout-stderr-streams.html
    class Subprocess

      # Create new subprocess and execute command there
      #
      # @param cmd [String] command to be executed
      def initialize(cmd)
        # standard input is not used
        Open3.popen3(cmd) do |_stdin, stdout, stderr, thread|
          { :out => stdout, :err => stderr }.each do |key, stream|
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
    # @param cmd [Array] command array to be executed
    # @return [String] produced output from executed command
    def run_cmd(cmd)
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
    # @param region [String] Region in Amazon AWS
    # @return [Aws::CloudFormation::Resource]
    def cfn_client(region)
      raise RuntimeError, 'Unable to proceed without region' if region && region.empty?
      client = Aws::CloudFormation::Client.new(region: region)
      Aws::CloudFormation::Resource.new(client: client)
    end

    # Wait until stack gets created
    #
    # @param cfn [Aws::CloudFormation::Resource] accessor for cloudformation resource
    # @param stack_name [String] name of the stack
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
    # @param stack [Aws::CloudFormation::Stack] cloudformation stack instance
    # @param key [String] resource identifier (key)
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
    # @param stack [Aws::CloudFormation::Stack] cloudformation stack instance
    # @param keys [Array] list of resource identifiers (keys)
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
    # @param stack [Aws::CloudFormation::Stack] cloudformation stack instance
    # @param keys [Array] list of keys
    def generate_parameters(stack, keys)
      keys.map do |k|
        v = get_resource(stack,k)
        { :parameter_key => k, :parameter_value => v }
      end
    end


    # Call script
    #
    # @param region [String] AWS region identifier
    # @param dependent_stack_name [String] name of the stack current stack depends on
    # @param script_path [String] path to script
    # @param keys [Array] keys
    # @param prepend_args [String] prepend arguments
    # @param append_args [String] append arguments
    # @deprecated this method is no longer used
    def cfn_call_script(region,
                    dependent_stack_name,
                    script_path,
                    keys,
                    prepend_args: '',
                    append_args: '')

      cfn = cfn_client(region)
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
    # @param region [String] AWS region identifier
    # @param dependent_stack_name [String] name of the stack current stack depends on
    # @param template [String] template name
    # @param stack_name [String] stack name
    # @param keys [Array] keys
    # @param extra_parameters [Array] additional parameters
    # @return [Aws::CloudFormation::Resource]
    # @deprecated this method is no longer used
    def cfn_create_stack(region,
                     dependent_stack_name,
                     template,
                     stack_name,
                     keys: [],
                     extra_parameters:[])

      cfn = cfn_client(region)
      stack = wait_stack(cfn, dependent_stack_name)

      extra_parameters_cleaned = extra_parameters.map do |x|
        if x.has_key? 'ParameterKey'
          { :parameter_key => x['ParameterKey'], :parameter_value => x['ParameterValue']}
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

  end # module Helpers
end # module Enscalator