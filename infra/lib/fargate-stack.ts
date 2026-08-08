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

    // Sumsub IDV credentials — a JSON secret with three keys: `appToken`,
    // `secretKey` (signs our calls out) and `webhookSecret` (verifies their
    // calls in). Created out-of-band like the APNs key, and referenced by ARN
    // through context so a plain deploy never carries a credential in source:
    //   cdk deploy GojoGoFargateStack -c sumsubSecretArn=arn:aws:secretsmanager:...
    //
    // Absent — the default — the backend gets no Sumsub env at all, the `kyc`
    // module reports itself unconfigured, and identity falls back to document
    // upload + human review exactly as it did before the module existed. That
    // fallback is deliberate: a half-configured IDV integration must not be
    // able to block partner onboarding.
    const sumsubSecretArn =
      (this.node.tryGetContext('sumsubSecretArn') as string | undefined) ?? '';
    const sumsubSecret = sumsubSecretArn
      ? secretsmanager.Secret.fromSecretCompleteArn(this, 'Sumsub', sumsubSecretArn)
      : undefined;

    // Stripe credentials — a JSON secret with three keys: `secretKey` (signs our
    // calls out), `webhookSecret` (verifies their calls in) and `publishableKey`
    // (handed to the iOS client, public by design but kept together with its
    // siblings so one rotation touches one place). Referenced by ARN through
    // context, like Sumsub above:
    //   cdk deploy GojoGoFargateStack -c stripeSecretArn=arn:aws:secretsmanager:...
    //
    // Absent — the default — the backend gets no Stripe env at all and the
    // `payments` module reports itself unconfigured: the wallet ledger still
    // works for internal movements, but nothing can charge a card or pay out.
    // That split is the point. External money is the only part that needs a
    // vendor, so an environment without keys must still be able to run every
    // internal flow rather than failing at startup.
    //
    // `webhookSecret` may legitimately be empty on the first deploy: Stripe only
    // mints it once the endpoint exists and answers, so the order is deploy →
    // create endpoint → put the whsec_ into the secret → deploy again. Signature
    // verification is what refuses to run without it, not the whole module.
    const stripeSecretArn =
      (this.node.tryGetContext('stripeSecretArn') as string | undefined) ?? '';
    const stripeSecret = stripeSecretArn
      ? secretsmanager.Secret.fromSecretCompleteArn(this, 'Stripe', stripeSecretArn)
      : undefined;

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
    sumsubSecret?.grantRead(executionRole);
    stripeSecret?.grantRead(executionRole);

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
        // Trust & safety (2e M5): a moderator suspending an account, and a
        // person deleting their own. Disabling is not deleting — the Cognito
        // user survives, so both are reversible, which is what makes the
        // 30-day deletion grace period and a lifted suspension possible.
        // GlobalSignOut is the other half of a disable: without it the refresh
        // token already on the device keeps minting access tokens for the
        // pool's whole refresh window, and a "closed" account keeps working.
        'cognito-idp:AdminDisableUser',
        'cognito-idp:AdminEnableUser',
        'cognito-idp:AdminUserGlobalSignOut',
      ],
      resources: [props.userPool.userPoolArn],
    }));
    taskRole.addToPolicy(new iam.PolicyStatement({ actions: ['sns:Publish'], resources: ['*'] }));

    // Madeleine's inference (MADELEINE-INFERENCE.md §10). Bedrock on-demand is
    // the production route; the assistant module's ModelClient calls it as the
    // task, with no credential of its own — which is why nothing is added to
    // CDK_SECRET_ARGS for this and why there is no new context flag to forget.
    // Bedrock auth is this role and nothing else, so unlike Sumsub or Stripe
    // there is no way to ship Madeleine half-configured (deploy-backend.sh's
    // 2026-07-30 lesson, which this grant is deliberately not repeating).
    //
    // THE OPENAI-COMPATIBLE ENDPOINT IS A DIFFERENT SERVICE, WITH A DIFFERENT
    // ACTION, ON A DIFFERENT RESOURCE. This is the correction that matters, and
    // an earlier version of this comment asserted the opposite — that
    // `bedrock:InvokeModel` "covers the bedrock-mantle path too, both authorize
    // as InvokeModel". It does not. Measured against the live endpoint on
    // 2026-08-08 with a correctly signed request, `bedrock-mantle` answers:
    //
    //   not authorized to perform: bedrock-mantle:CreateInference
    //   on resource: arn:aws:bedrock-mantle:us-east-1:<account>:project/default
    //
    // Note what is *not* in that ARN: a model. The mantle surface authorizes
    // per project, not per model, so there is no model-scoping to be had on
    // this statement and narrowing it by model id is not a thing that exists.
    // `project/*` rather than `project/default` because the project is chosen
    // by the endpoint, not by us, and a second one appearing would look exactly
    // like an outage.
    //
    // Getting this wrong is loud rather than silent — every turn ends in a 401
    // and the assistant module reports an honest turn_error — which is the one
    // mercy compared to the 2026-07-30 Sumsub failure. It is still a deploy
    // where Madeleine does nothing at all.
    taskRole.addToPolicy(new iam.PolicyStatement({
      actions: ['bedrock-mantle:CreateInference'],
      resources: [`arn:aws:bedrock-mantle:${this.region}:${this.account}:project/*`],
    }));

    // Precautionary, and deliberately kept despite nothing calling Converse
    // today. IAM reports only the *first* denial it hits, so the error above
    // proves mantle needs CreateInference and proves nothing either way about
    // whether it then authorizes the underlying model invocation as well. This
    // costs a scoped statement; the alternative costs a deploy, a 401, and a
    // second deploy. Delete it once a live turn has been observed succeeding
    // without it — not before.
    //
    // TWO resource ARNs per model, and both are load-bearing where they apply.
    // A cross-region-inference model is invoked through an *inference profile*
    // (`us.…`, account-scoped, this region), and Bedrock routes the call to a
    // *foundation model* in whichever US region has capacity. Grant only the
    // profile and the first invocation works until it routes elsewhere; grant
    // only us-east-1's foundation model and it breaks the moment it leaves the
    // region. Hence the `*` region on the foundation-model ARN — those ARNs
    // carry no account id by design.
    //
    // Now scoped to the two providers the eval actually chose (§9: qwen3-235b
    // for the brain, ministral-3-8b for the sidekick), replacing the
    // `meta.llama*` prefixes that predate that decision — Meta was never
    // invocable and is not what ships. Prefixes rather than the two exact ids
    // because mantle's model ids are not identical to the foundation-model ids
    // (`qwen.qwen3-235b-a22b-2507` does not appear in list-foundation-models at
    // all), so an exact-id policy would be a guess at a name we cannot read.
    taskRole.addToPolicy(new iam.PolicyStatement({
      actions: [
        'bedrock:InvokeModel',
        'bedrock:InvokeModelWithResponseStream',
      ],
      resources: [
        `arn:aws:bedrock:*::foundation-model/qwen.*`,
        `arn:aws:bedrock:*::foundation-model/mistral.*`,
        `arn:aws:bedrock:${this.region}:${this.account}:inference-profile/us.qwen.*`,
        `arn:aws:bedrock:${this.region}:${this.account}:inference-profile/us.mistral.*`,
      ],
    }));

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

    // Empty unless a deploy explicitly asks for it — see the two WORLD_ vars below.
    const worldDevOtpCode =
      (this.node.tryGetContext('worldDevOtpCode') as string | undefined) ?? '';

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
        // Phone verification. `worldDevOtpCode` is a **universal
        // phone-verification bypass**: anyone who knows the code verifies any
        // number, as anyone. It exists because SNS SMS is not usable in this
        // account (sandbox — only pre-verified destinations), which leaves the
        // fallback as the only way through.
        //
        // The two variables are set together and never separately. The backend
        // honours the code only while SMS is off (WorldProperties.hasDevCode),
        // so a deploy that set just the code would ship a dead switch, and one
        // that set just the flag would turn verification off with nothing in its
        // place. One context flag drives both, which makes the misconfiguration
        // WorldSmsSender.announce() warns about unrepresentable from here.
        //
        // Unset the flag the day SNS SMS leaves the sandbox — see PROGRESS #3.
        //   cdk deploy GojoGoFargateStack -c worldDevOtpCode=424242
        WORLD_OTP_DEV_CODE: worldDevOtpCode,
        WORLD_SMS_ENABLED: worldDevOtpCode ? 'false' : 'true',
        WORLD_SMS_SENDER_ID: 'GojoGo',
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
        // Which Sumsub verification level applicants are put through. Must name
        // a level that exists in the cockpit; not a secret, so it stays here
        // where it can be changed without touching the credential.
        SUMSUB_LEVEL_NAME:
          (this.node.tryGetContext('sumsubLevelName') as string | undefined)
          ?? 'id-and-liveness',
      },
      secrets: {
        DB_PASSWORD: ecs.Secret.fromSecretsManager(props.database.secret!, 'password'),
        APNS_KEY_BASE64: ecs.Secret.fromSecretsManager(apnsSecret),
        PARTNER_ADMIN_TOKEN: ecs.Secret.fromSecretsManager(partnerAdminSecret),
        // Spread, not listed: with no secret configured these keys are absent
        // entirely, which is what leaves the kyc module off rather than on with
        // empty credentials.
        ...(sumsubSecret
          ? {
              SUMSUB_APP_TOKEN: ecs.Secret.fromSecretsManager(sumsubSecret, 'appToken'),
              SUMSUB_SECRET_KEY: ecs.Secret.fromSecretsManager(sumsubSecret, 'secretKey'),
              SUMSUB_WEBHOOK_SECRET:
                ecs.Secret.fromSecretsManager(sumsubSecret, 'webhookSecret'),
            }
          : {}),
        // Same spread-not-listed shape as Sumsub: no secret configured means the
        // keys are absent rather than present-and-empty, which is what the
        // payments module reads to decide it is unconfigured.
        ...(stripeSecret
          ? {
              STRIPE_SECRET_KEY: ecs.Secret.fromSecretsManager(stripeSecret, 'secretKey'),
              STRIPE_WEBHOOK_SECRET:
                ecs.Secret.fromSecretsManager(stripeSecret, 'webhookSecret'),
              STRIPE_PUBLISHABLE_KEY:
                ecs.Secret.fromSecretsManager(stripeSecret, 'publishableKey'),
            }
          : {}),
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
