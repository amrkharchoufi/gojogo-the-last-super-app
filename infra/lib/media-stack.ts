import * as cdk from 'aws-cdk-lib';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

/**
 * User media: S3 bucket written via backend-presigned PUT URLs.
 *
 * Reads SHOULD go through CloudFront, but this AWS account is not yet
 * verified for CloudFront (new-account restriction; AWS Support must lift
 * it). Until then objects under media/* are public-read straight from S3.
 * Once support verifies the account, flip ENABLE_CLOUDFRONT to true and
 * redeploy GojoGoMediaStack + GojoGoAppStack — the app picks up the new
 * domain via the MEDIA_CDN_DOMAIN env var; keys/URLs keep the same paths.
 */
const ENABLE_CLOUDFRONT = false;

export class GojoGoMediaStack extends cdk.Stack {
  readonly bucket: s3.Bucket;
  /** Domain that serves uploaded objects (CloudFront when enabled, else S3). */
  readonly publicDomain: string;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    this.bucket = new s3.Bucket(this, 'UserMedia', {
      bucketName: `gojogo-user-media-${this.account}`,
      blockPublicAccess: ENABLE_CLOUDFRONT
        ? s3.BlockPublicAccess.BLOCK_ALL
        : new s3.BlockPublicAccess({
            blockPublicAcls: true,
            ignorePublicAcls: true,
            blockPublicPolicy: false,
            restrictPublicBuckets: false,
          }),
      cors: [
        {
          allowedMethods: [s3.HttpMethods.PUT, s3.HttpMethods.GET, s3.HttpMethods.HEAD],
          allowedOrigins: ['*'],
          allowedHeaders: ['*'],
          maxAge: 3600,
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    if (ENABLE_CLOUDFRONT) {
      const distribution = new cloudfront.Distribution(this, 'MediaCdn', {
        defaultBehavior: {
          origin: origins.S3BucketOrigin.withOriginAccessControl(this.bucket),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        },
        priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
        comment: 'GojoGo user media',
      });
      this.publicDomain = distribution.distributionDomainName;
    } else {
      this.bucket.addToResourcePolicy(
        new iam.PolicyStatement({
          actions: ['s3:GetObject'],
          resources: [this.bucket.arnForObjects('media/*')],
          principals: [new iam.AnyPrincipal()],
        }),
      );
      this.publicDomain = this.bucket.bucketRegionalDomainName;
    }

    new cdk.CfnOutput(this, 'BucketName', { value: this.bucket.bucketName });
    new cdk.CfnOutput(this, 'MediaPublicDomain', { value: this.publicDomain });
  }
}
