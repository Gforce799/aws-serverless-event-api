import json
import os
import time
import uuid

import boto3

dynamodb = boto3.resource("dynamodb")
events = boto3.client("events")


def lambda_handler(event, context):
    table_name = os.environ["TABLE_NAME"]
    bus_name = os.environ["BUS_NAME"]
    body = event.get("body") or "{}"
    payload = json.loads(body)
    event_id = str(uuid.uuid4())
    now = str(int(time.time()))

    table = dynamodb.Table(table_name)
    table.put_item(
        Item={
            "pk": f"event#{event_id}",
            "sk": now,
            "payload": payload,
        }
    )

    events.put_events(
        Entries=[
            {
  "Source": "application.api",
                "DetailType": "PortfolioEventAccepted",
                "Detail": json.dumps({"event_id": event_id}),
                "EventBusName": bus_name,
            }
        ]
    )

    return {
        "statusCode": 202,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"event_id": event_id, "status": "accepted"}),
    }
