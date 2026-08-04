import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import * as apigwv2 from 'aws-cdk-lib/aws-apigatewayv2';
import { WebSocketLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import { WebSocketLambdaAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import { Construct } from 'constructs';

export interface GojoGoMessagingStackProps extends cdk.StackProps {
  userPool: cognito.UserPool;
  userPoolClient: cognito.UserPoolClient;
}

/**
 * My World messaging platform (ARCHITECTURE.md §4/§8): a single DynamoDB table
 * plus an API Gateway WebSocket API for real-time server->client delivery.
 *
 * - The table holds conversations, memberships, messages, poll/reaction state
 *   AND the WebSocket connection registry (keyed by Cognito subject). The
 *   Spring `messaging` module owns all durable writes; the $connect/$disconnect
 *   Lambdas here own only the connection lifecycle.
 * - $connect is guarded by a Cognito-JWT request authorizer (token in the query
 *   string). The backend fans out to live connections via the @connections
 *   management API (grant added in the app stack, which also owns the instance
 *   role).
 */
export class GojoGoMessagingStack extends cdk.Stack {
  readonly table: dynamodb.Table;
  readonly webSocketApi: apigwv2.WebSocketApi;
  readonly webSocketStage: apigwv2.WebSocketStage;

  constructor(scope: Construct, id: string, props: GojoGoMessagingStackProps) {
    super(scope, id, props);

    this.table = new dynamodb.Table(this, 'MessagingTable', {
      tableName: 'gojogo-messaging',
      partitionKey: { name: 'pk', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'sk', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      // Sweeps stale WebSocket connection rows (see the $connect Lambda's TTL).
      timeToLiveAttribute: 'ttl',
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
    // One GSI serves two namespaced access patterns: a user's conversations
    // newest-first (gsi1pk=USERCONV#{uid}) and a conversation's messages in
    // time order (gsi1pk=CONVMSG#{cid}).
    this.table.addGlobalSecondaryIndex({
      indexName: 'gsi1',
      partitionKey: { name: 'gsi1pk', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'gsi1sk', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    const issuerUri = `https://cognito-idp.${this.region}.amazonaws.com/${props.userPool.userPoolId}`;

    // $connect authorizer: spends the single-use connect ticket from ?token=
    // (and still accepts a Cognito ID token while older builds are in the wild —
    // see the Lambda's own header for why the parameter keeps that name).
    const authorizerFn = new lambda.Function(this, 'WsAuthorizer', {
      functionName: 'gojogo-ws-authorizer',
      runtime: lambda.Runtime.NODEJS_22_X,
      handler: 'authorizer.handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '..', 'lambda', 'ws')),
      timeout: cdk.Duration.seconds(10),
      environment: {
        COGNITO_ISSUER_URI: issuerUri,
        COGNITO_APP_CLIENT_ID: props.userPoolClient.userPoolClientId,
        // Tickets live in the same table as the connection registry.
        MESSAGING_TABLE: this.table.tableName,
        // Flip to 'false' once the ticket-aware iOS build is adopted; that
        // closes the last path where an ID token can reach a query string.
        WS_ALLOW_TOKEN_AUTH: 'true',
      },
    });
    // Exactly one permission, on the table only. Spending a ticket is a single
    // DeleteItem returning the old row — read and destroy in one atomic call,
    // which is what makes it single-use — so that is all this function may do.
    //
    // Deliberately not grantWriteData: that also hands out PutItem, UpdateItem
    // and BatchWriteItem across the table *and every index*. This Lambda is the
    // one piece of the messaging system that runs on an unauthenticated,
    // attacker-supplied credential, and the table it is reaching into holds the
    // conversations and the connection registry. Write access there would let a
    // compromise forge messages or reroute somebody's live socket; delete access
    // to a ticket row lets it do its job and nothing else.
    authorizerFn.addToRolePolicy(new iam.PolicyStatement({
      actions: ['dynamodb:DeleteItem'],
      resources: [this.table.tableArn],
    }));

    // $connect / $disconnect handler: maintains the connection registry.
    const connectionFn = new lambda.Function(this, 'WsConnections', {
      functionName: 'gojogo-ws-connections',
      runtime: lambda.Runtime.NODEJS_22_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '..', 'lambda', 'ws')),
      timeout: cdk.Duration.seconds(10),
      environment: { MESSAGING_TABLE: this.table.tableName },
    });
    this.table.grantReadWriteData(connectionFn);

    this.webSocketApi = new apigwv2.WebSocketApi(this, 'WorldSocket', {
      apiName: 'gojogo-messaging',
      connectRouteOptions: {
        integration: new WebSocketLambdaIntegration('ConnectIntegration', connectionFn),
        authorizer: new WebSocketLambdaAuthorizer('JwtAuthorizer', authorizerFn, {
          identitySource: ['route.request.querystring.token'],
        }),
      },
      disconnectRouteOptions: {
        integration: new WebSocketLambdaIntegration('DisconnectIntegration', connectionFn),
      },
    });

    // Nothing here disables authorizer result caching, and nothing needs to:
    // WebSocket APIs do not cache authorizer results at all. API Gateway rejects
    // AuthorizerResultTtlInSeconds outright on a WEBSOCKET-protocol API
    // ("cannot be set for WEBSOCKET protocol Apis"), and CDK synth does not
    // catch it, so setting it to 0 defensively fails the deploy rather than
    // hardening anything.
    //
    // Worth stating because it is load-bearing for the connect ticket: every
    // $connect invokes the authorizer, so a spent ticket is always re-checked
    // against DynamoDB and a replay always loses. If this API ever becomes an
    // HTTP API, caching returns as a real concern and must be set to 0 there.

    this.webSocketStage = new apigwv2.WebSocketStage(this, 'ProdStage', {
      webSocketApi: this.webSocketApi,
      stageName: 'prod',
      autoDeploy: true,
    });

    new cdk.CfnOutput(this, 'MessagingTableName', { value: this.table.tableName });
    // wss:// URL the iOS client connects to.
    new cdk.CfnOutput(this, 'WebSocketUrl', { value: this.webSocketStage.url });
    // https:// URL the backend POSTs to for @connections fan-out.
    new cdk.CfnOutput(this, 'WebSocketCallbackUrl', { value: this.webSocketStage.callbackUrl });
  }
}
