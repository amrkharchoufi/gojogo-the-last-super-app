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

    // Task role: the app's own runtime permissions (was the App Runner instance role).
    const taskRole = new iam.Role(this, 'TaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
    });
    props.mediaBucket.grantPut(taskRole);
    props.mediaBucket.grantDelete(taskRole);
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
      image: ecs.ContainerImage.fromEcrRepository(props.repository, 'latest'),
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
      },
      secrets: {
        DB_PASSWORD: ecs.Secret.fromSecretsManager(props.database.secret!, 'password'),
        APNS_KEY_BASE64: ecs.Secret.fromSecretsManager(apnsSecret),
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
