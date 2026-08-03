import * as cdk from 'aws-cdk-lib';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

/**
 * User media: S3 bucket written via backend-presigned PUT URLs.
 *
 * Reads SHOULD go through CloudFront — it is faster everywhere (edge cache
 * near the user instead of one region), it is cheaper per GB than S3 egress,
 * and it lets the bucket go fully private behind an Origin Access Control
 * instead of serving `media/*` to the open internet. All of that is written
 * below and switched off, because the blocker is not code: a new AWS account
 * is not entitled to CloudFront until Support lifts the restriction.
 *
 * So it is a **deploy-time flag, not a source edit**:
 *
 *   cdk deploy GojoGoMediaStack GojoGoAppStack -c enableCloudfront=true
 *
 * Turning it on flips the bucket to BLOCK_ALL and drops the public-read policy
 * in the same change, so there is no window where both doors are open. The app
 * picks up the new host via MEDIA_CDN_DOMAIN and object keys are unchanged, so
 * previously uploaded URLs keep resolving.
 *
 * Deploying with the flag on before the account is entitled fails the stack
 * rather than half-applying it, which is the safe direction.
 */
export class GojoGoMediaStack extends cdk.Stack {
  readonly bucket: s3.Bucket;
  /** Domain that serves uploaded objects (CloudFront when enabled, else S3). */
  readonly publicDomain: string;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // `-c enableCloudfront=true`. Accepts the boolean or the string CDK context
    // gives you depending on whether it came from the CLI or cdk.json.
    const flag = this.node.tryGetContext('enableCloudfront');
    const ENABLE_CLOUDFRONT = flag === true || flag === 'true';

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
          // Wide open on purpose, and it grants nothing: a PUT still needs a
          // presigned URL the backend minted, and while reads are public a
          // browser origin rule cannot protect an object anyone can curl. The
          // thing that actually closes this is CloudFront + a private bucket
          // above, not a narrower list here.
          allowedMethods: [s3.HttpMethods.PUT, s3.HttpMethods.GET, s3.HttpMethods.HEAD],
          allowedOrigins: ['*'],
          allowedHeaders: ['*'],
          maxAge: 3600,
        },
      ],
      // RETAIN, not DESTROY: this holds avatars, post images and delivery proof
      // photos — user data that no migration can regenerate. A stack teardown
      // should leave an orphaned bucket to clean up by hand, not silently take
      // everybody's uploads with it.
      removalPolicy: cdk.RemovalPolicy.RETAIN,
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
