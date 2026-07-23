// My World messaging WebSocket connection handler: $connect / $disconnect.
//
// The registry lives in the same DynamoDB table the backend reads for fan-out
// (see com.gojogo.messaging.internal.MessagingRepository). Keyed by Cognito
// subject because that's what the authorizer proved:
//
//   SUB#{sub}   / CONN#{connectionId}   { connectionId, ttl }   <- fan-out reads these
//   CONN#{connectionId} / META          { sub }                 <- $disconnect reverse lookup
//
// A 24h TTL sweeps rows for sockets that vanished without a clean $disconnect;
// the backend also prunes on the first 410 Gone it sees for a connection.
//
// No npm deps: @aws-sdk/client-dynamodb ships in the Node 20 runtime.

import {
  DynamoDBClient,
  PutItemCommand,
  GetItemCommand,
  DeleteItemCommand,
} from '@aws-sdk/client-dynamodb';

const TABLE = process.env.MESSAGING_TABLE;
const ddb = new DynamoDBClient({});
const TTL_SECONDS = 24 * 60 * 60;

export const handler = async (event) => {
  const { routeKey, connectionId } = event.requestContext;
  try {
    if (routeKey === '$connect') {
      await connect(event, connectionId);
    } else if (routeKey === '$disconnect') {
      await disconnect(connectionId);
    }
    return { statusCode: 200 };
  } catch (err) {
    console.error(`WS ${routeKey} failed:`, err);
    return { statusCode: 500 };
  }
};

async function connect(event, connectionId) {
  const sub = event.requestContext.authorizer?.sub;
  if (!sub) throw new Error('No authorizer subject on $connect');
  const ttl = Math.floor(Date.now() / 1000) + TTL_SECONDS;

  await ddb.send(new PutItemCommand({
    TableName: TABLE,
    Item: {
      pk: { S: `SUB#${sub}` },
      sk: { S: `CONN#${connectionId}` },
      connectionId: { S: connectionId },
      ttl: { N: String(ttl) },
    },
  }));
  await ddb.send(new PutItemCommand({
    TableName: TABLE,
    Item: {
      pk: { S: `CONN#${connectionId}` },
      sk: { S: 'META' },
      sub: { S: sub },
      ttl: { N: String(ttl) },
    },
  }));
}

async function disconnect(connectionId) {
  const meta = await ddb.send(new GetItemCommand({
    TableName: TABLE,
    Key: { pk: { S: `CONN#${connectionId}` }, sk: { S: 'META' } },
  }));
  const sub = meta.Item?.sub?.S;
  if (sub) {
    await ddb.send(new DeleteItemCommand({
      TableName: TABLE,
      Key: { pk: { S: `SUB#${sub}` }, sk: { S: `CONN#${connectionId}` } },
    }));
  }
  await ddb.send(new DeleteItemCommand({
    TableName: TABLE,
    Key: { pk: { S: `CONN#${connectionId}` }, sk: { S: 'META' } },
  }));
}
