#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { GojoGoAuthStack } from '../lib/auth-stack';
import { GojoGoDataStack } from '../lib/data-stack';
import { GojoGoEcrStack } from '../lib/ecr-stack';
import { GojoGoAppStack } from '../lib/app-stack';

const app = new cdk.App();
const env = { account: '578109959809', region: 'us-east-1' };

const auth = new GojoGoAuthStack(app, 'GojoGoAuthStack', { env });
const data = new GojoGoDataStack(app, 'GojoGoDataStack', { env });
const ecr = new GojoGoEcrStack(app, 'GojoGoEcrStack', { env });

new GojoGoAppStack(app, 'GojoGoAppStack', {
  env,
  userPool: auth.userPool,
  database: data.database,
  repository: ecr.repository,
});
