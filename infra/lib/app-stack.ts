import * as cdk from 'aws-cdk-lib';
import * as apprunner from 'aws-cdk-lib/aws-apprunner';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

export interface GojoGoAppStackProps extends cdk.StackProps {
  userPool: cognito.UserPool;
  database: rds.DatabaseInstance;
  repository: ecr.Repository;
  mediaBucket: s3.Bucket;
  mediaCdnDomain: string;
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
              {
                name: 'COGNITO_ISSUER_URI',
                value: `https://cognito-idp.${this.region}.amazonaws.com/${props.userPool.userPoolId}`,
              },
              { name: 'MEDIA_BUCKET', value: props.mediaBucket.bucketName },
              { name: 'MEDIA_CDN_DOMAIN', value: props.mediaCdnDomain },
            ],
            runtimeEnvironmentSecrets: [
              // ":password::" extracts just that JSON key from the RDS-generated
              // secret - a bare secret ARN injects the whole {"username":...,
              // "password":...,"host":...} blob as the value instead.
              { name: 'DB_PASSWORD', value: `${props.database.secret!.secretArn}:password::` },
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
