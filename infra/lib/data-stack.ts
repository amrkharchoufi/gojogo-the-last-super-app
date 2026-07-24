import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import { Construct } from 'constructs';

/**
 * Dev-tier RDS Postgres, now **private** inside a dedicated VPC.
 *
 * History: a first private-networking attempt was reverted because App Runner's
 * VPC egress mode routes *all* outbound traffic through the connector, and the
 * VPC had no internet path, so Cognito/Apple JWT validation broke. The real fix
 * (done here) is a **NAT Gateway**: the App Runner connector lives in
 * PRIVATE_WITH_EGRESS subnets whose default route is the NAT, so the backend
 * still reaches Cognito, Apple JWKS, APNs and SNS over the internet, while RDS
 * is reachable *only* from the App Runner security group — never from the public
 * internet. S3 and DynamoDB traffic uses free VPC **gateway endpoints** instead
 * of the NAT, so the NAT only processes true internet egress (~$0.045/GB).
 *
 * Cost: 1 NAT Gateway ≈ $32-35/mo (single-AZ to keep it to one) + data
 * processing. See COSTS.md.
 */
export class GojoGoDataStack extends cdk.Stack {
  readonly database: rds.DatabaseInstance;
  readonly vpc: ec2.Vpc;
  /** SG the App Runner VPC connector attaches to (the only thing allowed into RDS). */
  readonly appRunnerSecurityGroup: ec2.SecurityGroup;
  /** RDS security group — the Fargate service adds its own ingress rule to this. */
  readonly databaseSecurityGroup: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Dedicated VPC. One NAT Gateway (single-AZ) keeps the recurring cost to a
    // single ~$32/mo charge; acceptable for a dev/pre-launch tier. Bump to
    // natGateways: 2 for AZ-redundant egress before a real launch.
    this.vpc = new ec2.Vpc(this, 'Vpc', {
      maxAzs: 2,
      natGateways: 1,
      subnetConfiguration: [
        { name: 'public', subnetType: ec2.SubnetType.PUBLIC, cidrMask: 24 },
        { name: 'app', subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS, cidrMask: 24 },
      ],
    });

    // Keep S3 + DynamoDB traffic off the NAT (and off the public internet):
    // gateway endpoints are free and route those services privately.
    this.vpc.addGatewayEndpoint('S3Endpoint', {
      service: ec2.GatewayVpcEndpointAwsService.S3,
    });
    this.vpc.addGatewayEndpoint('DynamoDbEndpoint', {
      service: ec2.GatewayVpcEndpointAwsService.DYNAMODB,
    });

    // The App Runner connector's SG — the sole source allowed into Postgres.
    this.appRunnerSecurityGroup = new ec2.SecurityGroup(this, 'AppRunnerSg', {
      vpc: this.vpc,
      description: 'GojoGo App Runner VPC connector',
      allowAllOutbound: true,
    });
    // Self-referencing inbound rule. With VPC egress, App Runner's health-check
    // path to the container's port traverses the connector ENIs, so the SG must
    // allow inbound from itself — without this the app runs fine (egress to RDS
    // works) but every health check on port 8080 fails and the deployment rolls
    // back. (Diagnosed the hard way during the private-RDS cutover.)
    this.appRunnerSecurityGroup.addIngressRule(
      this.appRunnerSecurityGroup,
      ec2.Port.allTraffic(),
      'App Runner VPC connector self - required for health checks',
    );

    const dbSecurityGroup = new ec2.SecurityGroup(this, 'DbSecurityGroup', {
      vpc: this.vpc,
      description: 'GojoGo Postgres - private, in-VPC ingress only',
      allowAllOutbound: true,
    });
    this.databaseSecurityGroup = dbSecurityGroup;
    // The App Runner connector SG (legacy) may still reach it; the Fargate
    // service adds its own ingress rule from GojoGoFargateStack.
    dbSecurityGroup.addIngressRule(
      this.appRunnerSecurityGroup,
      ec2.Port.tcp(5432),
      'Postgres from App Runner connector (legacy)',
    );

    // Construct ID bumped (V3 -> V4): moving the instance into a new VPC/subnet
    // group forces a full replace, since RDS subnet groups can't be updated in
    // place across VPCs. NOTE: deploying this REPLACES the database (test data
    // is lost — acceptable per PROGRESS.md); the endpoint + secret name change,
    // but App Runner reads both dynamically so it re-wires automatically.
    this.database = new rds.DatabaseInstance(this, 'PostgresV4', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_16,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T4G, ec2.InstanceSize.MICRO),
      vpc: this.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      publiclyAccessible: false,
      securityGroups: [dbSecurityGroup],
      // Secret name bumped alongside the construct ID (v3 -> v4) so it doesn't
      // collide with the not-yet-replaced v3 secret during the deploy.
      credentials: rds.Credentials.fromGeneratedSecret('gojogo', {
        secretName: 'gojogo/db-credentials-v4',
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
