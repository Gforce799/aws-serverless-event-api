module "this" {
    source = "../.."

    name        = "serverless-event-api"
    environment = "dev"

lambda_memory_mb       = 512
lambda_timeout_seconds = 15

    tags = {
      Owner      = "platform-team"
      CostCenter = "portfolio"
    }
  }
