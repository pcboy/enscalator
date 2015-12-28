module Enscalator
  module Plugins
    # Elasticsearch related configuration
    module ElasticsearchOpsworks
      include Enscalator::Helpers

      def elasticsearch_init(app_name, ssh_key: , os: 'Amazon Linux 2015.09', cookbook: 'https://github.com/en-japan/opsworks-elasticsearch-cookbook.git') 

        parameter "ES#{app_name}ChefCookbook",
                  Default: cookbook,
                  Description: 'GitURL',
                  Type: 'String'

        parameter "ES#{app_name}InstanceDefaultOs",
                  Default: os,
                  Description: "The stack s default operating system, which is installed on every instance unless you specify a different operating system when you create the instance.",
                  Type: 'String'

        parameter "EB#{app_name}SshKeyName",
                  Default: ssh_key, 
                  Description: "SSH key name for EC2 instances.",
                  Type: 'String'
        
        resource "InstanceRole",
          "Type": "AWS::IAM::InstanceProfile",
          "Properties": {
            "Path": "/",
            "Roles": [
              {
                "Ref": "OpsWorksEC2Role"
              }
            ]
          }

        resource "ServiceRole",
          "Type": "AWS::IAM::Role",
          "Properties": {
            "AssumeRolePolicyDocument": {
              "Statement": [
                {
                  "Effect": "Allow",
                  "Principal": {
                    "Service": [
                      "opsworks.amazonaws.com"
                    ]
                  },
                  "Action": [
                    "sts:AssumeRole"
                  ]
                }
              ]
            },
            "Path": "/",
            "Policies": [
              {
                "PolicyName": "#{app_name}-opsworks-service",
                "PolicyDocument": {
                  "Statement": [
                    {
                      "Effect": "Allow",
                      "Action": [
                        "ec2:*",
                        "iam:PassRole",
                        "cloudwatch:GetMetricStatistics",
                        "elasticloadbalancing:*"
                      ],
                      "Resource": "*"
                    }
                  ]
                }
              }
            ]
          }


        resource "OpsWorksEC2Role",
          "Type": "AWS::IAM::Role",
          "Properties": {
            "AssumeRolePolicyDocument": {
              "Statement": [
                {
                  "Effect": "Allow",
                  "Principal": {
                    "Service": [
                      "ec2.amazonaws.com"
                    ]
                  },
                  "Action": [
                    "sts:AssumeRole"
                  ]
                }
              ]
            },
            "Path": "/",
            "Policies": [
              {
                "PolicyName": "#{app_name}-opsworks-ec2-role",
                "PolicyDocument": {
                  "Statement": [
                    {
                      "Effect": "Allow",
                      "Action": [
                        "ec2:DescribeInstances",
                        "ec2:DescribeRegions",
                        "ec2:DescribeSecurityGroups",
                        "ec2:DescribeTags",
                        "cloudwatch:PutMetricData"
                      ],
                      "Resource": "*"
                    }
                  ]
                }
              }
            ]
          }


        security_group_vpc('elasticsearchtest',"so that ES cluster can find other nodes",vpc.id)


        stack_name = "#{app_name}-ES"
        resource "ESStack",
          Type: "AWS::OpsWorks::Stack",
          Properties: {
            Name: stack_name,
            VpcId: vpc.id,
            DefaultSubnetId: ref_resource_subnets.first,
            "ConfigurationManager": {
              "Name": "Chef",
              "Version": "12"
            },
            "UseCustomCookbooks": "true",
            "CustomCookbooksSource": {
              "Type": "git",
              "Url": ref("ES#{app_name}ChefCookbook")
            },
            DefaultOs: ref("ES#{app_name}InstanceDefaultOs"),
            DefaultRootDeviceType: "ebs",
            DefaultSshKeyName: ref("EB#{app_name}SshKeyName"),
            CustomJson: {
              "java": {
                "jdk_version": "8",
                "oracle": {
                  "accept_oracle_download_terms": "true"
                },
                "accept_license_agreement": "true",
                "install_flavor": "oracle"
              },
              "elasticsearch": {
                "plugins": [
                  "analysis-kuromoji",
                  "cloud-aws",
                  { name: 'elasticsearch-head', url: 'mobz/elasticsearch-head' }
                ],
                "cluster": {
                  "name": "#{app_name}-elasticsearch"
                },
                "gateway": {
                  "expected_nodes": 1
                },
                "discovery": {
                  "type": "ec2",
                  "zen": {
                    "minimum_master_nodes": 1,
                    "ping": {
                      "multicast": {
                        "enabled": false
                      }
                    }
                  },
                  "ec2": {
                    "tag": {
                      "opsworks:stack": stack_name,
                    }
                  }
                },
                "path": {
                  "data": "/mnt/elasticsearch-data"
                },
                "cloud": {
                  "aws": {
                    "region": region
                  }
                },
                "custom_config": {
                  "cluster.routing.allocation.awareness.attributes": "rack_id"
                }
              }
            },
            ServiceRoleArn: {
              "Fn::GetAtt": [
                "ServiceRole",
                "Arn"
              ]
            },
            "DefaultInstanceProfileArn": {
              "Fn::GetAtt": [
                "InstanceRole",
                "Arn"
              ]
            }
          }

        resource "ESLayer",
          "Type": "AWS::OpsWorks::Layer",
          "Properties": {
            "StackId": {
              "Ref": "ESStack"
            },
            "Name": "Search",
            "Type": "custom",
            "Shortname": "search",
            "CustomRecipes": {
              "Setup": [
                "apt",
                "ark",
                "elasticsearch",
                "java",
                "layer-custom::esplugins"
              ]
            },
            "EnableAutoHealing": "true",
            "AutoAssignElasticIps": "false",
            "AutoAssignPublicIps": "false",
            "VolumeConfigurations": [
              {
                "MountPoint": "/mnt/elasticsearch-data",
                "NumberOfDisks": 1,
                "VolumeType": "gp2",
                "Size": 100
              }
            ],
            "CustomSecurityGroupIds": [
              {
                "Fn::GetAtt": [
                  "elasticsearchtest",
                  "GroupId"
                ]
              }, 
              ref_private_security_group
            ]
          }
      end
    end # module Elasticsearch
  end # module Plugins
end # module Enscalator
