import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import * as apigwv2 from 'aws-cdk-lib/aws-apigatewayv2';
import { WebSocketLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import { WebSocketLambdaAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
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

    // $connect authorizer: validates the Cognito ID token from ?token=.
    const authorizerFn = new lambda.Function(this, 'WsAuthorizer', {
      functionName: 'gojogo-ws-authorizer',
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'authorizer.handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '..', 'lambda', 'ws')),
      timeout: cdk.Duration.seconds(10),
      environment: {
        COGNITO_ISSUER_URI: issuerUri,
        COGNITO_APP_CLIENT_ID: props.userPoolClient.userPoolClientId,
      },
    });

    // $connect / $disconnect handler: maintains the connection registry.
    const connectionFn = new lambda.Function(this, 'WsConnections', {
      functionName: 'gojogo-ws-connections',
      runtime: lambda.Runtime.NODEJS_20_X,
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
