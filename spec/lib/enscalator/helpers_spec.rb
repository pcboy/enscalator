require 'spec_helper'

describe Enscalator::Helpers do
  # Fixture for testing all helpers
  class TestFixture
    include Enscalator::Helpers
  end

  test_fixture = TestFixture.new

  it 'creates valid cloudformation client' do
    client = test_fixture.cfn_client('us-east-1')
    expect(client.class).to be Aws::CloudFormation::Client
  end

  it 'raises exception if region is not provided for cloudformation client' do
    expect { test_fixture.cfn_client('') }.to raise_exception ArgumentError
    expect { test_fixture.cfn_client(nil) }.to raise_exception ArgumentError
  end

  it 'creates valid cloudformation resource accessor' do
    client = test_fixture.cfn_client('us-east-1')
    resource = test_fixture.cfn_resource(client)
    expect(resource.class).to be Aws::CloudFormation::Resource
  end

  it 'raises exception when resource accessor is used without valid client' do
    expect { test_fixture.cfn_resource('') }.to raise_exception ArgumentError
    expect { test_fixture.cfn_resource(nil) }.to raise_exception ArgumentError
  end

  it 'creates valid client for ec2' do
    client = test_fixture.ec2_client('us-east-1')
    expect(client.class).to be Aws::EC2::Client
  end

  it 'raises exception when region is not provided for ec2 client' do
    expect { test_fixture.ec2_client('') }.to raise_exception ArgumentError
    expect { test_fixture.ec2_client(nil) }.to raise_exception ArgumentError
  end

  it 'creates valid client for route53' do
    client = test_fixture.route53_client('us-east-1')
    expect(client.class).to be Aws::Route53::Client
  end

  it 'raises exception when region is not provided for route53 client' do
    expect { test_fixture.route53_client('') }.to raise_exception ArgumentError
    expect { test_fixture.route53_client(nil) }.to raise_exception ArgumentError
  end

  it 'finds amis using ec2 client and default parameters' do
    VCR.use_cassette 'aws_sdk_ec2_client_find_ami', :tag => :aws_credentials do
      client = test_fixture.ec2_client('us-east-1')
      images = test_fixture.find_ami(client).images
      assert_ami(images.sample.image_id)
    end
  end

  it 'raises exception when trying to find ami providing not valid ec2 client' do
    expect { test_fixture.find_ami(nil) }.to raise_exception ArgumentError
    expect { test_fixture.find_ami('') }.to raise_exception ArgumentError
    expect { test_fixture.find_ami(test_fixture.cfn_client('us-east-1')) }.to raise_exception ArgumentError
  end

  it 'generates ssh key name from app_name, region and stack_name' do
    test_app_name = 'TestBox'
    test_region = 'africa-1'
    test_stack_name = 'BatchProcessing'
    generated_key_name = test_fixture.gen_ssh_key_name(test_app_name,
                                                       test_region,
                                                       test_stack_name)
    expect(generated_key_name).to include(test_app_name.underscore)
    expect(generated_key_name).to include(test_region.underscore)
    expect(generated_key_name).to include(test_stack_name.underscore)
    expect(generated_key_name).to match Regexp.new(/[a-z0-9_]+/)
  end
end
