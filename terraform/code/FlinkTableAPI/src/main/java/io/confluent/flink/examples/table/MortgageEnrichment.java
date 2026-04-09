package io.confluent.flink.examples.table;

import io.confluent.flink.plugin.ConfluentSettings;
import io.confluent.flink.plugin.ConfluentTableDescriptor;

import org.apache.flink.table.api.DataTypes;
import org.apache.flink.table.api.Schema;
import org.apache.flink.table.api.TableEnvironment;

import static org.apache.flink.table.api.Expressions.*;

public class MortgageEnrichment {

    private static final String ENRICHED_MORTGAGE_TABLE = "enriched_mortgage_applications";

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("Usage: MortgageEnrichment <catalog_name> <database_name>");
            System.exit(1);
        }

        String catalogName = args[0];
        String databaseName = args[1];

        // Use ConfluentSettings as the entrypoint for configuration
        ConfluentSettings.Builder settings =
                ConfluentSettings.newBuilderFromResource("/prod.properties");
        settings.setOption("sql.local-time-zone", "UTC");
        settings.setContextName("mortgage-enrichment");

        TableEnvironment env = TableEnvironment.create(settings.build());

        // Set up catalog and database using command-line arguments
        env.useCatalog(catalogName);
        env.useDatabase(databaseName);

        // Create the enriched mortgage applications table
        env.createTable(
                ENRICHED_MORTGAGE_TABLE,
                ConfluentTableDescriptor.forManaged()
                        .schema(
                                Schema.newBuilder()
                                        .column("application_id", DataTypes.STRING().notNull())
                                        .column("customer_email", DataTypes.STRING())
                                        .column("borrower_name", DataTypes.STRING())
                                        .column("applicant_id", DataTypes.STRING())
                                        .column("income", DataTypes.DOUBLE())
                                        .column("payslips", DataTypes.STRING())
                                        .column("loan_amount", DataTypes.DOUBLE())
                                        .column("property_address", DataTypes.STRING())
                                        .column("property_state", DataTypes.STRING())
                                        .column("property_value", DataTypes.DOUBLE())
                                        .column("employment_status", DataTypes.STRING())
                                        .column("credit_score", DataTypes.DOUBLE())
                                        .column("credit_utilization", DataTypes.DOUBLE())
                                        .column("open_credit_accounts", DataTypes.DOUBLE())
                                        .column("recent_defaults", DataTypes.DOUBLE())
                                        .column("debt_to_income_ratio", DataTypes.DOUBLE())
                                        .column("application_ts", DataTypes.TIMESTAMP_LTZ(3))
                                        .watermark(
                                                "application_ts",
                                                $("application_ts").minus(lit(5).seconds()))
                                        .build())
                        .option("kafka.retention.time", "0")
                        .option("value.format", "avro-registry")
                        .build());

        // Use SQL for the temporal join — the Table API doesn't support
        // temporal join syntax directly, and the CDC table in Debezium retract
        // mode requires a temporal join to avoid retractions in the output.
        env.executeSql("""
                INSERT INTO enriched_mortgage_applications
                SELECT
                  m.application_id,
                  m.customer_email,
                  m.customer_name AS borrower_name,
                  m.applicant_id,
                  CAST(m.income AS DOUBLE) AS income,
                  m.payslips,
                  CAST(m.loan_amount AS DOUBLE) AS loan_amount,
                  m.property_address,
                  m.property_state,
                  CAST(m.property_value AS DOUBLE) AS property_value,
                  m.employment_status,
                  c.credit_score AS credit_score,
                  c.credit_utilization AS credit_utilization,
                  c.open_credit_accounts AS open_credit_accounts,
                  c.public_records AS recent_defaults,
                  CAST(ROUND((CAST(m.loan_amount AS DECIMAL(10, 2)) / CAST(m.income AS DECIMAL(10, 2))) * 100, 2) AS DOUBLE) AS debt_to_income_ratio,
                  m.application_ts
                FROM `mortgage_applications` m
                JOIN `PROD.public.applicant_credit_score` FOR SYSTEM_TIME AS OF m.`application_ts` AS c
                ON m.applicant_id = c.applicant_id
                """);
    }
}
