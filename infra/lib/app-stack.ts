import * as cdk from 'aws-cdk-lib';
import * as apigwv2 from 'aws-cdk-lib/aws-apigatewayv2';
import * as apprunner from 'aws-cdk-lib/aws-apprunner';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';

export interface GojoGoAppStackProps extends cdk.StackProps {
  userPool: cognito.UserPool;
  userPoolClient: cognito.UserPoolClient;
  database: rds.DatabaseInstance;
  repository: ecr.Repository;
  mediaBucket: s3.Bucket;
  mediaCdnDomain: string;
  messagingTable: dynamodb.Table;
  webSocketStage: apigwv2.WebSocketStage;
  /** VPC the backend joins so it can reach the now-private RDS. */
  vpc: ec2.Vpc;
  /** SG the connector attaches to (allowed into the RDS security group). */
  appRunnerSecurityGroup: ec2.SecurityGroup;
}

export class GojoGoAppStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: GojoGoAppStackProps) {
    super(scope, id, props);

    const ecrAccessRole = new iam.Role(this, 'EcrAccessRole', {
      roleName: 'GojoGoAppRunnerEcrAccess',
      assumedBy: new iam.ServicePrincipal('build.apprunner.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName(
          'service-role/AWSAppRunnerServicePolicyForECRAccess',
        ),
      ],
    });

    const instanceRole = new iam.Role(this, 'InstanceRole', {
      roleName: 'GojoGoAppRunnerInstance',
      assumedBy: new iam.ServicePrincipal('tasks.apprunner.amazonaws.com'),
    });
    // Lets the running container read the RDS-generated password at startup
    // instead of it being passed as a plaintext runtime env var.
    props.database.secret!.grantRead(instanceRole);
    // Presigned PUT URLs are signed with the instance role's credentials.
    props.mediaBucket.grantPut(instanceRole);
    // Orphan-upload sweep deletes unreferenced objects (report-only until
    // MEDIA_CLEANUP_DELETE=true — see MediaCleanupJob).
    props.mediaBucket.grantDelete(instanceRole);
    // Native Apple sign-in: the backend validates Apple's identity token, then
    // (for a brand-new user only) creates the email-keyed Cognito user, and
    // mints tokens via the passwordless CUSTOM_AUTH flow. Scoped to this pool.
    instanceRole.addToPolicy(
      new iam.PolicyStatement({
        actions: [
          'cognito-idp:AdminGetUser',
          'cognito-idp:AdminCreateUser',
          'cognito-idp:AdminSetUserPassword',
          'cognito-idp:AdminInitiateAuth',
          'cognito-idp:AdminRespondToAuthChallenge',
        ],
        resources: [props.userPool.userPoolArn],
      }),
    );
    // My World messaging: the backend owns all durable writes to the DynamoDB
    // single table, and pushes real-time events to live sockets via the
    // WebSocket @connections management API.
    props.messagingTable.grantReadWriteData(instanceRole);
    props.webSocketStage.grantManagementApiAccess(instanceRole);
    // My World phone verification: send the OTP by SMS via SNS. SMS publish to a
    // raw phone number has no resource ARN, so it must be scoped to "*".
    instanceRole.addToPolicy(
      new iam.PolicyStatement({
        actions: ['sns:Publish'],
        resources: ['*'],
      }),
    );
    // APNs push signing key (.p8, base64) — stored in Secrets Manager, never in
    // source. Created out-of-band (see PROGRESS.md APNs checklist); referenced
    // by name so its value stays only in Secrets Manager and is injected into
    // the container at runtime, like DB_PASSWORD.
    const apnsSecret = secretsmanager.Secret.fromSecretCompleteArn(this, 'ApnsKey',
      'arn:aws:secretsmanager:us-east-1:578109959809:secret:gojogo/apns-key-cmCUid');
    apnsSecret.grantRead(instanceRole);

    // Explicit autoscaling so the service's warm floor / burst ceiling / per-
    // instance concurrency are codified and tunable (the AWS default is an
    // opaque min=1/max=25/concurrency=100). App Runner keeps `minSize`
    // instances provisioned (billed at the reduced idle-memory rate), so a
    // request never waits on a from-zero cold start; raise `minSize` before a
    // launch spike if you want more always-warm headroom.
    const autoScaling = new apprunner.CfnAutoScalingConfiguration(this, 'AutoScaling', {
      autoScalingConfigurationName: 'gojogo-backend',
      minSize: 1,           // always-warm instances (idle-billed) — no cold start
      maxSize: 4,           // burst ceiling
      maxConcurrency: 80,   // requests per instance before scaling out
    });

    // VPC connector: puts the backend inside the VPC so it can reach the private
    // RDS. App Runner VPC egress routes ALL outbound through here; the connector's
    // PRIVATE_WITH_EGRESS subnets have a NAT default route so Cognito/Apple/APNs
    // still resolve. (S3 + DynamoDB use the VPC's free gateway endpoints.)
    const vpcConnector = new apprunner.CfnVpcConnector(this, 'VpcConnector', {
      vpcConnectorName: 'gojogo-backend',
      subnets: props.vpc.selectSubnets({
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      }).subnetIds,
      securityGroups: [props.appRunnerSecurityGroup.securityGroupId],
    });

    const service = new apprunner.CfnService(this, 'Service', {
      serviceName: 'gojogo-backend',
      autoScalingConfigurationArn: autoScaling.attrAutoScalingConfigurationArn,
      networkConfiguration: {
        egressConfiguration: {
          egressType: 'VPC',
          vpcConnectorArn: vpcConnector.attrVpcConnectorArn,
        },
      },
      sourceConfiguration: {
        authenticationConfiguration: { accessRoleArn: ecrAccessRole.roleArn },
        autoDeploymentsEnabled: false,
        imageRepository: {
          imageIdentifier: `${props.repository.repositoryUri}:latest`,
          imageRepositoryType: 'ECR',
          imageConfiguration: {
            port: '8080',
            runtimeEnvironmentVariables: [
              { name: 'DB_HOST', value: props.database.dbInstanceEndpointAddress },
              { name: 'DB_PORT', value: '5432' },
              { name: 'DB_NAME', value: 'gojogo' },
              { name: 'DB_USER', value: 'gojogo' },
              {
                name: 'COGNITO_ISSUER_URI',
                value: `https://cognito-idp.${this.region}.amazonaws.com/${props.userPool.userPoolId}`,
              },
              // Consumed by the native-Apple token exchange (AuthController /
              // AppleAuthService). APPLE_AUDIENCE is the iOS bundle id, which is
              // the `aud` of a native Sign in with Apple identity token.
              { name: 'COGNITO_USER_POOL_ID', value: props.userPool.userPoolId },
              { name: 'COGNITO_APP_CLIENT_ID', value: props.userPoolClient.userPoolClientId },
              { name: 'APPLE_AUDIENCE', value: 'com.gojo.gojogo' },
              { name: 'MEDIA_BUCKET', value: props.mediaBucket.bucketName },
              { name: 'MEDIA_CDN_DOMAIN', value: props.mediaCdnDomain },
              // Orphan-upload sweep. Ships in report-only mode: it logs the
              // unreferenced objects it *would* delete. Flip MEDIA_CLEANUP_DELETE
              // to 'true' only after those logs confirm no in-use media is listed.
              { name: 'MEDIA_CLEANUP_DELETE', value: 'false' },
              { name: 'MESSAGING_TABLE', value: props.messagingTable.tableName },
              // https:// @connections endpoint for WebSocket fan-out.
              { name: 'MESSAGING_WS_ENDPOINT', value: props.webSocketStage.callbackUrl },
              // My World phone OTP: sender id for the SMS, plus a dev code that
              // works alongside the real SMS code while SNS SMS is sandboxed.
              // TODO: clear WORLD_OTP_DEV_CODE before any real launch.
              { name: 'WORLD_SMS_SENDER_ID', value: 'GojoGo' },
              { name: 'WORLD_OTP_DEV_CODE', value: '424242' },
              // APNs push — non-secret coordinates (the .p8 itself is a secret,
              // injected below). Sandbox host for development builds.
              { name: 'APNS_KEY_ID', value: '9W7A69BV93' },
              { name: 'APNS_TEAM_ID', value: 'T8348X4CNY' },
              { name: 'APNS_BUNDLE_ID', value: 'com.gojo.gojogo' },
              { name: 'APNS_PRODUCTION', value: 'true' },
              // Exposes /actuator/health/liveness (+ /readiness) — the liveness
              // group excludes the DB indicator, so App Runner's health probe
              // gates on "app is up", not DB latency. See healthCheckConfiguration.
              { name: 'MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED', value: 'true' },
            ],
            runtimeEnvironmentSecrets: [
              // ":password::" extracts just that JSON key from the RDS-generated
              // secret - a bare secret ARN injects the whole {"username":...,
              // "password":...,"host":...} blob as the value instead.
              { name: 'DB_PASSWORD', value: `${props.database.secret!.secretArn}:password::` },
              // Base64 of the APNs .p8 key — the whole secret value.
              { name: 'APNS_KEY_BASE64', value: apnsSecret.secretArn },
            ],
          },
        },
      },
      instanceConfiguration: {
        cpu: '1024',
        memory: '2048',
        instanceRoleArn: instanceRole.roleArn,
      },
      // Probe the LIVENESS group, not the full health. The full /actuator/health
      // includes a DataSource indicator that blocks up to 30s (Hikari timeout)
      // whenever the DB is briefly slow, returning 503 and forcing App Runner to
      // roll the deployment back — which is exactly what broke the private-RDS
      // cutover. Liveness reflects only "is the app process up", so the deploy
      // gate no longer depends on DB latency. Requires the probes group env below.
      healthCheckConfiguration: {
        protocol: 'HTTP',
        path: '/actuator/health/liveness',
        interval: 10,
        timeout: 5,
        healthyThreshold: 1,
        unhealthyThreshold: 8,
      },
    });

    new cdk.CfnOutput(this, 'ServiceUrl', { value: `https://${service.attrServiceUrl}` });
    new cdk.CfnOutput(this, 'ServiceArn', { value: service.attrServiceArn });
  }
}
