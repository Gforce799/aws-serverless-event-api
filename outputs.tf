output "api_endpoint" {
  description = "HTTP API endpoint."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "events_table_name" {
  description = "DynamoDB table name."
  value       = aws_dynamodb_table.events.name
}

output "event_bus_name" {
  description = "EventBridge bus name."
  value       = aws_cloudwatch_event_bus.this.name
}
