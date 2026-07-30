import * as cdk from 'aws-cdk-lib';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as apigwv2 from 'aws-cdk-lib/aws-apigatewayv2';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';

export interface GojoGoFargateStackProps extends cdk.StackProps {
  userPool: cognito.UserPool;
  userPoolClient: cognito.UserPoolClient;
  database: rds.DatabaseInstance;
  repository: ecr.Repository;
  mediaBucket: s3.Bucket;
  mediaCdnDomain: string;
  messagingTable: dynamodb.Table;
  webSocketStage: apigwv2.WebSocketStage;
  vpc: ec2.Vpc;
  /** RDS security group — this stack adds its own service ingress rule to it. */
  databaseSecurityGroup: ec2.SecurityGroup;
  /** Public API hostname, e.g. api.example.com. */
  domainName: string;
  /** ARN of a pre-validated ACM cert for domainName (DNS is external to AWS). */
  certificateArn: string;
  /**
   * Backend image tag to run. Day-to-day deploys are done by
   * `scripts/deploy-backend.sh`, which registers a new task definition revision
   * pinned to an immutable tag (the git SHA) — that is what makes `--rollback`
   * work. A `cdk deploy` re-asserts the task definition and would otherwise
   * knock the service back to a mutable `latest`, so pass the running tag:
   *   cdk deploy GojoGoFargateStack -c imageTag=$(./scripts/deploy-backend.sh --current)
   */
  imageTag: string;
}

/**
 * The backend on ECS/Fargate, inside the VPC, reaching the **private** RDS
 * directly (no App Runner VPC-egress hack — that proved unstable). A public
 * Application Load Balancer terminates HTTPS (ACM cert on the user's domain)
 * and forwards to the Fargate task on :8080. This replaces GojoGoAppStack.
 */
export class GojoGoFargateStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: GojoGoFargateStackProps) {
    super(scope, id, props);

    const apnsSecret = secretsmanager.Secret.fromSecretCompleteArn(this, 'ApnsKey',
      'arn:aws:secretsmanager:us-east-1:578109959809:secret:gojogo/apns-key-cmCUid');

    // Partner review (PartnerAdminController). Unlike the economy cleanup token
    // — which is passed per-deploy precisely so a plain deploy turns cleanup
    // back off — this one has to *persist*: approving merchants is ongoing work,
    // and a deploy that quietly emptied it would take the review queue offline
    // and, with it, any way for delivery to gain a restaurant. So it's a
    // generated secret rather than context, which also keeps it out of the task
    // definition in cleartext. Read it once with:
    //   aws secretsmanager get-secret-value --secret-id gojogo/partner-admin-token \
    //     --query SecretString --output text
    const partnerAdminSecret = new secretsmanager.Secret(this, 'PartnerAdminToken', {
      secretName: 'gojogo/partner-admin-token',
      description: 'X-Partner-Admin-Token for /v1/partner/admin/** (KYC review)',
      generateSecretString: { passwordLength: 48, excludePunctuation: true },
    });

    // --- Roles -------------------------------------------------------------
    // Execution role: pulls the image + reads the container secrets at launch.
    const executionRole = new iam.Role(this, 'ExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });
    props.database.secret!.grantRead(executionRole);
    apnsSecret.grantRead(executionRole);
    partnerAdminSecret.grantRead(executionRole);

    // Task role: the app's own runtime permissions (was the App Runner instance role).
    const taskRole = new iam.Role(this, 'TaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
    });
    props.mediaBucket.grantPut(taskRole);
    props.mediaBucket.grantDelete(taskRole);
    // Read, for the KYC papers. A presigned URL carries the *signer's*
    // permissions, so without this the reviewer's link is signed correctly and
    // still 403s — which is exactly what it did until the 2e M2 E2E fetched one
    // (public media/* is world-readable and never needed this, so nothing else
    // did). Scoped to the private prefix: the app has no business bulk-reading
    // user media it doesn't already hand out by URL.
    props.mediaBucket.grantRead(taskRole, 'private/*');
    props.messagingTable.grantReadWriteData(taskRole);
    props.webSocketStage.grantManagementApiAccess(taskRole);
    taskRole.addToPolicy(new iam.PolicyStatement({
      actions: [
        'cognito-idp:AdminGetUser',
        'cognito-idp:AdminCreateUser',
        'cognito-idp:AdminSetUserPassword',
        'cognito-idp:AdminInitiateAuth',
        'cognito-idp:AdminRespondToAuthChallenge',
      ],
      resources: [props.userPool.userPoolArn],
    }));
    taskRole.addToPolicy(new iam.PolicyStatement({ actions: ['sns:Publish'], resources: ['*'] }));

    // --- Cluster + task ----------------------------------------------------
    const cluster = new ecs.Cluster(this, 'Cluster', { vpc: props.vpc, clusterName: 'gojogo' });

    const logGroup = new logs.LogGroup(this, 'LogGroup', {
      logGroupName: '/ecs/gojogo-backend',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const taskDef = new ecs.FargateTaskDefinition(this, 'Task', {
      cpu: 1024,
      memoryLimitMiB: 2048,
      executionRole,
      taskRole,
    });

    taskDef.addContainer('backend', {
      image: ecs.ContainerImage.fromEcrRepository(props.repository, props.imageTag),
      portMappings: [{ containerPort: 8080 }],
      logging: ecs.LogDrivers.awsLogs({ logGroup, streamPrefix: 'app' }),
      environment: {
        DB_HOST: props.database.dbInstanceEndpointAddress,
        DB_PORT: '5432',
        DB_NAME: 'gojogo',
        DB_USER: 'gojogo',
        COGNITO_ISSUER_URI: `https://cognito-idp.${this.region}.amazonaws.com/${props.userPool.userPoolId}`,
        COGNITO_USER_POOL_ID: props.userPool.userPoolId,
        COGNITO_APP_CLIENT_ID: props.userPoolClient.userPoolClientId,
        APPLE_AUDIENCE: 'com.gojo.gojogo',
        MEDIA_BUCKET: props.mediaBucket.bucketName,
        MEDIA_CDN_DOMAIN: props.mediaCdnDomain,
        MEDIA_CLEANUP_DELETE: 'false',
        MESSAGING_TABLE: props.messagingTable.tableName,
        MESSAGING_WS_ENDPOINT: props.webSocketStage.callbackUrl,
        WORLD_SMS_SENDER_ID: 'GojoGo',
        WORLD_OTP_DEV_CODE: '424242',
        APNS_KEY_ID: '9W7A69BV93',
        APNS_TEAM_ID: 'T8348X4CNY',
        APNS_BUNDLE_ID: 'com.gojo.gojogo',
        APNS_PRODUCTION: 'true',
        MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED: 'true',
        // Dev-only marketplace cleanup (EconomyAdminController). Empty here on
        // purpose: with no token, /v1/economy/admin/** 404s. Pass one for the
        // deploy that does the wipe, then deploy again without the flag —
        // defaulting to '' means a plain deploy always turns cleanup back off.
        //   cdk deploy GojoGoFargateStack -c economyAdminToken=$(openssl rand -hex 24)
        ECONOMY_ADMIN_TOKEN:
          (this.node.tryGetContext('economyAdminToken') as string | undefined) ?? '',
        // Browser origins allowed to call the API (comma-separated). Empty
        // means no CORS headers at all, which is right while the only client is
        // the iOS app — native apps aren't subject to CORS. GoJoAdmin is a
        // browser client, so its origin goes here when it exists:
        //   cdk deploy GojoGoFargateStack -c webAllowedOrigins=https://admin.gojogo.app
        WEB_ALLOWED_ORIGINS:
          (this.node.tryGetContext('webAllowedOrigins') as string | undefined) ?? '',
      },
      secrets: {
        DB_PASSWORD: ecs.Secret.fromSecretsManager(props.database.secret!, 'password'),
        APNS_KEY_BASE64: ecs.Secret.fromSecretsManager(apnsSecret),
        PARTNER_ADMIN_TOKEN: ecs.Secret.fromSecretsManager(partnerAdminSecret),
      },
    });

    // The service's own SG (created here, so the ALB→service ingress rule stays
    // within this stack and doesn't create a DataStack↔FargateStack cycle).
    const serviceSg = new ec2.SecurityGroup(this, 'ServiceSg', {
      vpc: props.vpc,
      description: 'GojoGo Fargate backend service',
      allowAllOutbound: true,
    });
    // Let the service into the private RDS. Declared here (one-way dependency on
    // the DataStack SG id) rather than as an addIngressRule on the DataStack SG,
    // which would make DataStack depend back on this stack.
    new ec2.CfnSecurityGroupIngress(this, 'DbIngressFromService', {
      groupId: props.databaseSecurityGroup.securityGroupId,
      ipProtocol: 'tcp',
      fromPort: 5432,
      toPort: 5432,
      sourceSecurityGroupId: serviceSg.securityGroupId,
      description: 'Postgres from Fargate backend',
    });

    const service = new ecs.FargateService(this, 'Service', {
      cluster,
      serviceName: 'gojogo-backend',
      taskDefinition: taskDef,
      desiredCount: 1,
      securityGroups: [serviceSg],
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      assignPublicIp: false,
      minHealthyPercent: 100,
      maxHealthyPercent: 200,
      healthCheckGracePeriod: cdk.Duration.seconds(120),
    });

    // --- ALB + HTTPS -------------------------------------------------------
    // DNS is external to AWS, so the cert is requested + validated out-of-band
    // (see FARGATE_MIGRATION.md) and imported here by ARN.
    const cert = acm.Certificate.fromCertificateArn(this, 'Cert', props.certificateArn);

    const alb = new elbv2.ApplicationLoadBalancer(this, 'Alb', {
      vpc: props.vpc,
      internetFacing: true,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
    });

    const httpsListener = alb.addListener('Https', {
      port: 443,
      protocol: elbv2.ApplicationProtocol.HTTPS,
      certificates: [cert],
    });
    httpsListener.addTargets('Backend', {
      port: 8080,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targets: [service],
      deregistrationDelay: cdk.Duration.seconds(15),
      healthCheck: {
        // Liveness only — decoupled from DB latency (the App Runner lesson).
        path: '/actuator/health/liveness',
        healthyHttpCodes: '200',
        interval: cdk.Duration.seconds(15),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 5,
      },
    });
    // Redirect plain HTTP to HTTPS.
    alb.addListener('Http', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultAction: elbv2.ListenerAction.redirect({
        protocol: 'HTTPS',
        port: '443',
        permanent: true,
      }),
    });

    // External DNS: point ${domainName} at this ALB with a CNAME (or ALIAS) at
    // your DNS provider. The ALB DNS name is stable for the life of the ALB.
    new cdk.CfnOutput(this, 'ApiUrl', { value: `https://${props.domainName}` });
    new cdk.CfnOutput(this, 'AlbDnsCnameTarget', { value: alb.loadBalancerDnsName });
  }
}
