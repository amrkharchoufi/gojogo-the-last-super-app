#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { GojoGoAuthStack } from '../lib/auth-stack';
import { GojoGoDataStack } from '../lib/data-stack';
import { GojoGoEcrStack } from '../lib/ecr-stack';
import { GojoGoMediaStack } from '../lib/media-stack';
import { GojoGoMessagingStack } from '../lib/messaging-stack';
import { GojoGoAppStack } from '../lib/app-stack';
import { GojoGoFargateStack } from '../lib/fargate-stack';

const app = new cdk.App();
const env = { account: '578109959809', region: 'us-east-1' };

const auth = new GojoGoAuthStack(app, 'GojoGoAuthStack', { env });
const data = new GojoGoDataStack(app, 'GojoGoDataStack', { env });
const ecr = new GojoGoEcrStack(app, 'GojoGoEcrStack', { env });
const media = new GojoGoMediaStack(app, 'GojoGoMediaStack', { env });
const messaging = new GojoGoMessagingStack(app, 'GojoGoMessagingStack', {
  env,
  userPool: auth.userPool,
  userPoolClient: auth.userPoolClient,
});

new GojoGoAppStack(app, 'GojoGoAppStack', {
  env,
  userPool: auth.userPool,
  userPoolClient: auth.userPoolClient,
  database: data.database,
  repository: ecr.repository,
  mediaBucket: media.bucket,
  mediaCdnDomain: media.publicDomain,
  messagingTable: messaging.table,
  webSocketStage: messaging.webSocketStage,
  vpc: data.vpc,
  appRunnerSecurityGroup: data.appRunnerSecurityGroup,
});

// ECS/Fargate backend (private RDS) — the App Runner replacement. Only built
// when the domain + validated ACM cert ARN are supplied (DNS is external), e.g.:
//   cdk deploy GojoGoFargateStack \
//     -c domainName=api.example.com \
//     -c certificateArn=arn:aws:acm:us-east-1:578109959809:certificate/....
const domainName = app.node.tryGetContext('domainName');
const certificateArn = app.node.tryGetContext('certificateArn');
if (domainName && certificateArn) {
  new GojoGoFargateStack(app, 'GojoGoFargateStack', {
    env,
    userPool: auth.userPool,
    userPoolClient: auth.userPoolClient,
    database: data.database,
    repository: ecr.repository,
    mediaBucket: media.bucket,
    mediaCdnDomain: media.publicDomain,
    messagingTable: messaging.table,
    webSocketStage: messaging.webSocketStage,
    vpc: data.vpc,
    databaseSecurityGroup: data.databaseSecurityGroup,
    domainName,
    certificateArn,
  });
}
