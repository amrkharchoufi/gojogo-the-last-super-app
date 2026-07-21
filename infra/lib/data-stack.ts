import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import { Construct } from 'constructs';

/**
 * Dev-tier RDS Postgres in the default VPC.
 *
 * The milestone-1 IAM policy cannot create VPCs, NAT gateways, or App Runner
 * VPC connectors, so the instance is publicly accessible with a security group
 * open on 5432 — acceptable for a dev database with a strong password, to be
 * revisited when the stack moves to ECS/private networking.
 */
export class GojoGoDataStack extends cdk.Stack {
  readonly database: rds.DatabaseInstance;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const dbPassword = new cdk.CfnParameter(this, 'DbPassword', {
      type: 'String',
      noEcho: true,
      minLength: 16,
      description: 'Master password for the gojogo database user',
    });

    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', { isDefault: true });

    const dbSecurityGroup = new ec2.SecurityGroup(this, 'DbSecurityGroup', {
      vpc,
      description: 'GojoGo dev Postgres - public access, dev only',
      allowAllOutbound: true,
    });
    dbSecurityGroup.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(5432), 'Postgres (dev)');

    this.database = new rds.DatabaseInstance(this, 'Postgres', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_16,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T4G, ec2.InstanceSize.MICRO),
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      publiclyAccessible: true,
      securityGroups: [dbSecurityGroup],
      credentials: rds.Credentials.fromPassword(
        'gojogo',
        cdk.SecretValue.cfnParameter(dbPassword),
      ),
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
  }
}
