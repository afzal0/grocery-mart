# Epic 9, Story 9.9 — CloudWatch alarms for critical conditions. Thresholds prevent noise (a single
# transient failure below threshold does not page). Each alarm routes to the on-call SNS topic and
# references a runbook (see runbook.md). Apply with the platform's Terraform pipeline against AWS.

variable "oncall_sns_topic_arn" { type = string }
variable "log_group_name"       { type = string, default = "/grocery-mart/api" }

# --- Payment / Stripe webhook processing failures ---------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "webhook_failures" {
  name           = "grocery-mart-webhook-failures"
  log_group_name = var.log_group_name
  pattern        = "?\"invalid Stripe signature\" ?\"webhook\" ?\"payment\" ?\"ERROR\""
  metric_transformation {
    name      = "WebhookFailures"
    namespace = "GroceryMart/Payments"
    value     = "1"
  }
}
resource "aws_cloudwatch_metric_alarm" "payment_failures" {
  alarm_name          = "grocery-mart-payment-webhook-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "WebhookFailures"
  namespace           = "GroceryMart/Payments"
  period              = 300
  statistic           = "Sum"
  threshold           = 5            # >5 webhook failures in 5 min pages on-call
  alarm_description    = "Payment/Stripe webhook processing failures. Runbook: runbook.md#payments"
  alarm_actions       = [var.oncall_sns_topic_arn]
}

# --- RLS policy denials spike (possible tenant-isolation probe or bug) -------------------------
resource "aws_cloudwatch_log_metric_filter" "rls_denials" {
  name           = "grocery-mart-rls-denials"
  log_group_name = var.log_group_name
  pattern        = "\"row-level security\""
  metric_transformation {
    name      = "RlsDenials"
    namespace = "GroceryMart/Security"
    value     = "1"
  }
}
resource "aws_cloudwatch_metric_alarm" "rls_denial_spike" {
  alarm_name          = "grocery-mart-rls-denial-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RlsDenials"
  namespace           = "GroceryMart/Security"
  period              = 300
  statistic           = "Sum"
  threshold           = 20           # baseline is ~0; a spike is suspicious
  alarm_description    = "RLS denial spike — possible isolation probe. Runbook: runbook.md#security"
  alarm_actions       = [var.oncall_sns_topic_arn]
}

# --- Application 5xx error rate ----------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name          = "grocery-mart-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description    = "Elevated 5xx rate. Runbook: runbook.md#errors"
  alarm_actions       = [var.oncall_sns_topic_arn]
}

# --- Availability SLO breach (Story 9.14: 99.5% target) ---------------------------------------
resource "aws_cloudwatch_metric_alarm" "availability_slo" {
  alarm_name          = "grocery-mart-availability-slo"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description    = "No healthy hosts — availability at risk. Runbook: runbook.md#availability"
  alarm_actions       = [var.oncall_sns_topic_arn]
}
