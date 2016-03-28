require 'spec_helper'

describe Enscalator::Plugins::Route53 do
  describe '#create_healthcheck' do
    let(:app_name) { 'route53_healthcheck_test' }
    let(:description) { 'This is a template for route53 healthcheck test entries' }
    let(:healthcheck_template_fixture_default) do
      route53_test_app_name = app_name
      route53_test_description = description
      route53_test_template_name = app_name.humanize.delete(' ')
      gen_richtemplate(route53_test_template_name,
                       Enscalator::EnAppTemplateDSL) do
        @app_name = route53_test_app_name
        value(Description: route53_test_description)
        mock_availability_zones
      end
    end

    context 'when invoked with default parameters and fqdn' do
      it 'generates valid template with fqdn and empty ip address' do
        cmd_opts = default_cmd_opts(healthcheck_template_fixture_default.name,
                                    healthcheck_template_fixture_default.name.underscore)
        route53_template = healthcheck_template_fixture_default.new(cmd_opts)

        test_fqdn = 'somedomain.test.japan.en'
        route53_template.create_healthcheck(app_name,
                                            cmd_opts[:stack_name],
                                            fqdn: test_fqdn)
        dict = route53_template.instance_variable_get(:@dict)
        expect(dict[:Description]).to eq(description)
        expect(dict[:Resources]["#{app_name}Healthcheck"].empty?).to be_falsey
        test_resources = dict[:Resources]["#{app_name}Healthcheck"]
        expect(test_resources[:Type]).to eq('AWS::Route53::HealthCheck')
        config = test_resources[:Properties][:HealthCheckConfig]
        expect(config[:IPAddress]).to be_nil
        expect(config[:FullyQualifiedDomainName]).to eq(test_fqdn)
        tags = test_resources[:Properties][:HealthCheckTags]
        expect(tags)
          .to include(Key: 'Application', Value: app_name) && include(Key: 'Stack', Value: cmd_opts[:stack_name])
      end
    end

    context 'when invoked with default parameters and ip address' do
      it 'generates valid template with ip address and without fqdn' do
        cmd_opts = default_cmd_opts(healthcheck_template_fixture_default.name,
                                    healthcheck_template_fixture_default.name.underscore)
        route53_template = healthcheck_template_fixture_default.new(cmd_opts)
        test_ip_addr = '172.0.0.55'
        route53_template.create_healthcheck(app_name,
                                            cmd_opts[:stack_name],
                                            ip_address: test_ip_addr)

        dict = route53_template.instance_variable_get(:@dict)
        expect(dict[:Resources]["#{app_name}Healthcheck"].empty?).to be_falsey
        test_resources = dict[:Resources]["#{app_name}Healthcheck"]
        config = test_resources[:Properties][:HealthCheckConfig]
        expect(config[:FullyQualifiedDomainName]).to be_nil
        expect(config[:IPAddress]).to eq(test_ip_addr)
      end
    end

    context 'when invoked with not supported healthcheck type' do
      it 'raises a Runtime exception' do
        cmd_opts = default_cmd_opts(healthcheck_template_fixture_default.name,
                                    healthcheck_template_fixture_default.name.underscore)
        route53_template = healthcheck_template_fixture_default.new(cmd_opts)
        test_fqdn = 'nonvalid.type.japan.en'

        expect do
          route53_template.create_healthcheck(app_name,
                                              cmd_opts[:stack_name],
                                              fqdn: test_fqdn,
                                              type: 'UDP')
        end.to raise_exception(RuntimeError)
      end
    end
  end

  describe '#create_hosted_zone' do
    let(:app_name) { 'route53_hosted_zone_test' }
    let(:description) { 'This is a template for route53 hosted zone' }
    let(:hosted_zone_template_fixture_default) do
      route53_test_app_name = app_name
      route53_test_description = description
      route53_test_template_name = app_name.humanize.delete(' ')
      gen_richtemplate(route53_test_template_name,
                       Enscalator::EnAppTemplateDSL) do
        @app_name = route53_test_app_name
        value(Description: route53_test_description)
        mock_availability_zones
      end
    end

    # TODO: remove before adding tests and method implementation
    context 'when not implemented method gets invoked' do
      it 'raises Runtime exception' do
        cmd_opts = default_cmd_opts(
          hosted_zone_template_fixture_default.name,
          hosted_zone_template_fixture_default.name.underscore).merge(hosted_zone: 'private.enjapan.test')
        route53_template = hosted_zone_template_fixture_default.new(cmd_opts)
        expect { route53_template.create_hosted_zone }.to raise_exception(RuntimeError)
      end
    end
  end

  describe '#create_single_dns_record' do
    let(:app_name) { 'route53_dns_record_test' }
    let(:description) { 'This is a template for route53 test dns records' }
    let(:dns_record_template_fixture_default) do
      route53_test_app_name = app_name
      route53_test_description = description
      route53_test_template_name = app_name.humanize.delete(' ')
      gen_richtemplate(route53_test_template_name,
                       Enscalator::EnAppTemplateDSL) do
        @app_name = route53_test_app_name
        value(Description: route53_test_description)
        mock_availability_zones
      end
    end

    context 'when invoked with default parameters' do
      it 'generates resource template for single dns A record entry' do
        cmd_opts = default_cmd_opts(
          dns_record_template_fixture_default.name,
          dns_record_template_fixture_default.name.underscore).merge(hosted_zone: 'private.test')
        route53_template = dns_record_template_fixture_default.new(cmd_opts)
        test_record_name = 'test-entry-default'
        route53_template.create_single_dns_record(app_name,
                                                  cmd_opts[:stack_name],
                                                  cmd_opts[:hosted_zone],
                                                  test_record_name)
        dict = route53_template.instance_variable_get(:@dict)
        expect(dict[:Description]).to eq(description)
        expect(dict[:Resources]["#{app_name}Hostname"].empty?).to be_falsey
        test_resources = dict[:Resources]["#{app_name}Hostname"]
        expect(test_resources[:Type]).to eq('AWS::Route53::RecordSet')
        properties = test_resources[:Properties]
        expect(properties[:Name]).to eq(test_record_name)
        expect(properties[:HostedZoneName]).to eq(cmd_opts[:hosted_zone])
        expect(properties[:TTL]).to eq(300)
        expect(properties[:Type]).to eq('A')
        expect(properties[:ResourceRecords]).to eq(ref("#{app_name}PublicIpAddress"))
      end
    end

    context 'when invoked with default parameters without app_name' do
      it 'uses stack_name to generate application like name' do
        cmd_opts = default_cmd_opts(
          dns_record_template_fixture_default.name,
          dns_record_template_fixture_default.name.underscore).merge(hosted_zone: 'private.test')
        route53_template = dns_record_template_fixture_default.new(cmd_opts)

        test_record_name = 'test-entry-default'
        route53_template.create_single_dns_record(nil,
                                                  cmd_opts[:stack_name],
                                                  cmd_opts[:hosted_zone],
                                                  test_record_name)
        dict = route53_template.instance_variable_get(:@dict)
        expect(dict[:Description]).to eq(description)
        expected_name = cmd_opts[:stack_name].titleize.delete(' ')
        expect(dict[:Resources]["#{expected_name}Hostname"].empty?).to be_falsey
      end
    end

    context 'when invoked with type parameter set to non-default value' do
      it 'includes valid dns record type in generated template' do
        cmd_opts =
          default_cmd_opts(dns_record_template_fixture_default.name,
                           dns_record_template_fixture_default.name.underscore).merge(hosted_zone: 'private.test')
        route53_template = dns_record_template_fixture_default.new(cmd_opts)

        test_record_name = 'test-entry-valid-type-default'
        test_record_type = 'CNAME'

        route53_template.create_single_dns_record(app_name,
                                                  cmd_opts[:stack_name],
                                                  cmd_opts[:hosted_zone],
                                                  test_record_name,
                                                  type: test_record_type)
        dict = route53_template.instance_variable_get(:@dict)
        test_resources = dict[:Resources]["#{app_name}Hostname"]
        expect(test_resources[:Properties][:Type]).to eq(test_record_type)
      end

      it 'raises Runtime exception if supplied value is not valid' do
        cmd_opts =
          default_cmd_opts(dns_record_template_fixture_default.name,
                           dns_record_template_fixture_default.name.underscore).merge(hosted_zone: 'private.test')
        route53_template = dns_record_template_fixture_default.new(cmd_opts)
        test_record_name = 'test-entry-wrong-type-default'

        expect do
          route53_template.create_single_dns_record(app_name,
                                                    cmd_opts[:stack_name],
                                                    cmd_opts[:hosted_zone],
                                                    test_record_name,
                                                    type: 'MMX')
        end.to raise_exception(RuntimeError)

        expect do
          route53_template.create_single_dns_record(app_name,
                                                    cmd_opts[:stack_name],
                                                    cmd_opts[:hosted_zone],
                                                    test_record_name,
                                                    type: '')
        end.to raise_exception(RuntimeError)

        expect do
          route53_template.create_single_dns_record(app_name,
                                                    cmd_opts[:stack_name],
                                                    cmd_opts[:hosted_zone],
                                                    test_record_name,
                                                    type: {})
        end.to raise_exception(RuntimeError)
      end
    end

    context 'when invoked with healthcheck parameter with non-default value' do
      it 'includes valid healthcheck reference in generated template' do
        cmd_opts =
          default_cmd_opts(dns_record_template_fixture_default.name,
                           dns_record_template_fixture_default.name.underscore).merge(hosted_zone: 'private.test')
        route53_template = dns_record_template_fixture_default.new(cmd_opts)
        test_record_name = 'test-entry-healthy-default'
        test_healthcheck = "#{app_name}Healthcheck"
        route53_template.create_single_dns_record(app_name,
                                                  cmd_opts[:stack_name],
                                                  cmd_opts[:hosted_zone],
                                                  test_record_name,
                                                  healthcheck: ref(test_healthcheck))
        dict = route53_template.instance_variable_get(:@dict)
        test_resources = dict[:Resources]["#{app_name}Hostname"]
        expect(test_resources[:Properties][:HealthCheckId]).to eq(ref(test_healthcheck))
      end

      it 'raises Runtime exception if its not valid' do
        cmd_opts =
          default_cmd_opts(dns_record_template_fixture_default.name,
                           dns_record_template_fixture_default.name.underscore).merge(hosted_zone: 'private.test')
        route53_template = dns_record_template_fixture_default.new(cmd_opts)
        test_record_name = 'test-entry-nonhealthy-default'

        expect do
          route53_template.create_single_dns_record(app_name,
                                                    cmd_opts[:stack_name],
                                                    cmd_opts[:hosted_zone],
                                                    test_record_name,
                                                    healthcheck: [])
        end.to raise_exception(RuntimeError)
      end
    end
    context 'when invoked with alias_target parameter with non-default value' do
      it 'includes valid alias_target reference in generated template' do
        cmd_opts =
          default_cmd_opts(dns_record_template_fixture_default.name,
                           dns_record_template_fixture_default.name.underscore).merge(hosted_zone: 'private.test')
        route53_template = dns_record_template_fixture_default.new(cmd_opts)
        test_record_name = 'test-entry-aliastarget'
        test_aliastarget = {
          HostedZoneId: get_att('TestResource', 'CanonicalHostedZoneNameID'),
          DNSName: get_att('TestResource', 'CanonicalHostedZoneName')
        }
        route53_template.create_single_dns_record(app_name,
                                                  cmd_opts[:stack_name],
                                                  cmd_opts[:hosted_zone],
                                                  test_record_name,
                                                  alias_target: test_aliastarget)
        dict = route53_template.instance_variable_get(:@dict)
        test_resources = dict[:Resources]["#{app_name}Hostname"]
        expect(test_resources[:Properties][:AliasTarget]).to eq(test_aliastarget)
      end

      it 'raises Runtime exception if its not valid' do
        cmd_opts =
          default_cmd_opts(dns_record_template_fixture_default.name,
                           dns_record_template_fixture_default.name.underscore).merge(hosted_zone: 'private.test')
        route53_template = dns_record_template_fixture_default.new(cmd_opts)
        test_record_name = 'test-entry-aliastarget'
        expect do
          route53_template.create_single_dns_record(app_name,
                                                    cmd_opts[:stack_name],
                                                    cmd_opts[:hosted_zone],
                                                    test_record_name,
                                                    alias_target: [])
        end.to raise_exception(RuntimeError)

        expect do
          route53_template.create_single_dns_record(app_name,
                                                    cmd_opts[:stack_name],
                                                    cmd_opts[:hosted_zone],
                                                    test_record_name,
                                                    type: 'CNAME',
                                                    alias_target: {
                                                      HostedZoneId: 'test_zone_id'
                                                    })
        end.to raise_exception(RuntimeError)

        expect do
          route53_template.create_single_dns_record(app_name,
                                                    cmd_opts[:stack_name],
                                                    cmd_opts[:hosted_zone],
                                                    test_record_name,
                                                    alias_target: {
                                                      DNSName: 'test_zone_dns'
                                                    })
        end.to raise_exception(RuntimeError)
      end
    end
  end

  describe '#create_multiple_dns_records' do
    let(:app_name) { 'route53_multi_dns_record_test' }
    let(:description) { 'This is a template for route53 multiple test dns records' }
    let(:dns_multi_record_template_fixture_default) do
      route53_test_app_name = app_name
      route53_test_description = description
      route53_test_template_name = app_name.humanize.delete(' ')
      gen_richtemplate(route53_test_template_name,
                       Enscalator::EnAppTemplateDSL) do
        @app_name = route53_test_app_name
        value(Description: route53_test_description)
        mock_availability_zones
      end
    end

    # TODO: remove before adding tests and method implementation
    context 'when not implemented method gets invoked' do
      it 'raises Runtime exception' do
        cmd_opts = default_cmd_opts(
          dns_multi_record_template_fixture_default.name,
          dns_multi_record_template_fixture_default.name.underscore).merge(hosted_zone: 'private.enjapan.test')
        route53_template = dns_multi_record_template_fixture_default.new(cmd_opts)
        expect { route53_template.create_multiple_dns_records }.to raise_exception(RuntimeError)
      end
    end
  end
end