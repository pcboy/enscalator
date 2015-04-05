module Enscalator
  module Plugins
    module RDS

      # Amazon RDS instance
      #
      # @param db_name [String] database name
      # @param allocated_storage [Integer] size of instance primary storage
      # @param storage_type [String] instance storage type
      # @param instance_class [String] instance class (type)
      def rds_init(db_name,
                   allocated_storage: 5,
                   storage_type: 'gp2',
                   instance_class: 'db.m1.small')

        parameter_allocated_storage "RDS#{db_name}",
          default: allocated_storage,
          min: 5,
          max: 1024

        parameter_name "RDS#{db_name}"

        parameter_username "RDS#{db_name}"

        parameter_password "RDS#{db_name}"

        parameter_instance_class "RDS#{db_name}",
          default: instance_class,
          allowed_values: %w(db.m1.small db.m1.large db.m1.xlarge
                          db.m2.xlarge db.m2.2xlarge db.m2.4xlarge)

        parameter "RDS#{db_name}StorageType",
                  :Default => storage_type,
                  :Description => 'Storage type to be associated with the DB instance',
                  :Type => 'String',
                  :AllowedValues => %w{ gp2 standard io1 }

        resource "RDS#{db_name}SubnetGroup", :Type => 'AWS::RDS::DBSubnetGroup', :Properties => {
          :DBSubnetGroupDescription => 'Subnet group within VPC',
          :SubnetIds => [
            ref_resource_subnet_a,
            ref_resource_subnet_c
          ],
          :Tags => [{:Key => 'Name', :Value => "RDS#{db_name}SubnetGroup"}]
        }

        resource "RDS#{db_name}Instance", :Type => 'AWS::RDS::DBInstance', :Properties => {
          :Engine => 'MySQL',
          :PubliclyAccessible => 'false',
          :DBName => ref("RDS#{db_name}Name"),
          :MultiAZ => 'false',
          :MasterUsername => ref("RDS#{db_name}Username"),
          :MasterUserPassword => ref("RDS#{db_name}Password"),
          :DBInstanceClass => ref("RDS#{db_name}InstanceClass"),
          :VPCSecurityGroups => [ ref_resource_security_group ],
          :DBSubnetGroupName => ref("RDS#{db_name}SubnetGroup"),
          :AllocatedStorage => ref("RDS#{db_name}AllocatedStorage"),
          :StorageType => ref("RDS#{db_name}StorageType"),
          :Tags => [{:Key => "Name", :Value => "RDS#{db_name}Instance"}]
        }

        output "#{db_name}EndpointAddress",
          :Description => "#{db_name} Endpoint Address",
          :Value => get_att("RDS#{db_name}Instance", 'Endpoint.Address')

      end

    end # RDS
  end # Plugins
end # Enscalator
