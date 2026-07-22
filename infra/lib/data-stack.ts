import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import { Construct } from 'constructs';

/**
 * Dev-tier RDS Postgres in the default VPC, publicly accessible behind a
 * password-protected security group.
 *
 * A private-networking attempt (dedicated isolated VPC + App Runner VPC
 * connector) was tried and reverted: App Runner's VPC egress mode routes
 * *all* outbound traffic through the connector, not just VPC-bound traffic,
 * so an internet-isolated VPC broke Cognito JWT validation. The real fix
 * needs a NAT Gateway (~$32-35/mo) - deferred as not worth the recurring
 * cost at this stage; revisit alongside the ECS/Fargate migration.
 */
export class GojoGoDataStack extends cdk.Stack {
  readonly database: rds.DatabaseInstance;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', { isDefault: true });

    const dbSecurityGroup = new ec2.SecurityGroup(this, 'DbSecurityGroup', {
      vpc,
      description: 'GojoGo dev Postgres - public access, dev only',
      allowAllOutbound: true,
    });
    dbSecurityGroup.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(5432), 'Postgres (dev)');

    // Construct ID bumped again (V2 -> V3): any change to which VPC/subnets
    // a DatabaseInstance lives in must force a full replace, since RDS
    // subnet groups can't be updated in place across VPCs.
    this.database = new rds.DatabaseInstance(this, 'PostgresV3', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_16,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T4G, ec2.InstanceSize.MICRO),
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      publiclyAccessible: true,
      securityGroups: [dbSecurityGroup],
      // Name bumped alongside the construct ID (V2 -> V3) - Secrets Manager
      // treats the base name as the uniqueness key regardless of the random
      // ARN suffix, so reusing the old name collides with the not-yet-
      // -replaced PostgresV2 secret during this deploy.
      credentials: rds.Credentials.fromGeneratedSecret('gojogo', {
        secretName: 'gojogo/db-credentials-v3',
      }),
      databaseName: 'gojogo',
      allocatedStorage: 20,
      maxAllocatedStorage: 20,
      multiAz: false,
      backupRetention: cdk.Duration.days(0),
      deletionProtection: false,
      deleteAutomatedBackups: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    new cdk.CfnOutput(this, 'DbEndpoint', { value: this.database.dbInstanceEndpointAddress });
    new cdk.CfnOutput(this, 'DbSecretArn', { value: this.database.secret!.secretArn });
  }
}
