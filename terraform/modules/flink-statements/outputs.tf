output "enriched_mortgage_applications_statement" {
  description = "Enriched mortgage applications Flink statement name"
  value       = confluent_flink_statement.enriched_mortgage_applications.statement_name
}

output "applicant_payment_summary_statement" {
  description = "Applicant payment summary Flink statement name"
  value       = confluent_flink_statement.applicant_payment_summary.statement_name
}

output "enriched_mortgage_with_payments_statement" {
  description = "Enriched mortgage with payments Flink statement name"
  value       = confluent_flink_statement.enriched_mortgage_with_payments.statement_name
}

output "mortgage_validated_apps_statement" {
  description = "Mortgage validated apps Flink statement name"
  value       = confluent_flink_statement.mortgage_validated_apps.statement_name
}

output "mortgage_decisions_statement" {
  description = "Mortgage decisions Flink statement name"
  value       = confluent_flink_statement.mortgage_decisions.statement_name
}
