import * as cdk from 'aws-cdk-lib';
import * as apprunner from 'aws-cdk-lib/aws-apprunner';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as rds from 'aws-cdk-lib/aws-rds';
import { Construct } from 'constructs';

export interface GojoGoAppStackProps extends cdk.StackProps {
  userPool: cognito.UserPool;
  database: rds.DatabaseInstance;
  repository: ecr.Repository;
}

export class GojoGoAppStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: GojoGoAppStackProps) {
    super(scope, id, props);

    // Same value as GojoGoDataStack's DbPassword; passed to both at deploy time.
    const dbPassword = new cdk.CfnParameter(this, 'DbPassword', {
      type: 'String',
      noEcho: true,
      minLength: 16,
      description: 'Password for the gojogo database user (matches GojoGoDataStack)',
    });

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

    const service = new apprunner.CfnService(this, 'Service', {
      serviceName: 'gojogo-backend',
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
              { name: 'DB_PASSWORD', value: dbPassword.valueAsString },
              {
                name: 'COGNITO_ISSUER_URI',
                value: `https://cognito-idp.${this.region}.amazonaws.com/${props.userPool.userPoolId}`,
              },
            ],
          },
        },
      },
      instanceConfiguration: {
        cpu: '1024',
        memory: '2048',
        instanceRoleArn: instanceRole.roleArn,
      },
      healthCheckConfiguration: {
        protocol: 'HTTP',
        path: '/actuator/health',
        interval: 10,
        timeout: 5,
        healthyThreshold: 1,
        unhealthyThreshold: 5,
      },
    });

    new cdk.CfnOutput(this, 'ServiceUrl', { value: `https://${service.attrServiceUrl}` });
    new cdk.CfnOutput(this, 'ServiceArn', { value: service.attrServiceArn });
  }
}
