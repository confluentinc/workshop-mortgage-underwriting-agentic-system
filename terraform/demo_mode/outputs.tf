output "resource_ids" {
  value     = module.base.resource_ids
  sensitive = true
}

output "flink_exec_command" {
  value = module.base.flink_exec_command
}

output "webapp_endpoint" {
  value = module.base.webapp_endpoint
}

output "flink_statements" {
  description = "Names of deployed Flink statements"
  value = {
    enriched_mortgage_applications   = module.flink_statements.enriched_mortgage_applications_statement
    applicant_payment_summary        = module.flink_statements.applicant_payment_summary_statement
    enriched_mortgage_with_payments  = module.flink_statements.enriched_mortgage_with_payments_statement
    mortgage_validated_apps          = module.flink_statements.mortgage_validated_apps_statement
    mortgage_decisions               = module.flink_statements.mortgage_decisions_statement
  }
}
