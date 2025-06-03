package io.confluent.flink.examples.table;

import io.confluent.flink.plugin.ConfluentSettings;
import io.confluent.flink.plugin.ConfluentTableDescriptor;

import org.apache.flink.table.api.DataTypes;
import org.apache.flink.table.api.Schema;
import org.apache.flink.table.api.Table;
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
                                                "application_ts - INTERVAL '5' SECOND")
                                        .build())
                        .option("kafka.retention.time", "0")
                        .option("value.format", "avro-registry")
                        .build());

        Table enrichedApplications =
                env.from("mortgage_applications")
                        .select(
                                $("application_id"),
                                $("customer_email"),
                                $("customer_name"),
                                $("applicant_id"),
                                $("income"),
                                $("payslips"),
                                $("loan_amount"),
                                $("property_address"),
                                $("property_state"),
                                $("property_value"),
                                $("employment_status"),
                                $("application_ts"))
                        .join(
                                env.from("`PROD.SAMPLE.APPLICANT_CREDIT_SCORE`")
                                        .select(
                                                $("after")
                                                        .get("APPLICANT_ID")
                                                        .as("credit_applicant_id"),
                                                $("after").get("CREDIT_SCORE").as("CREDIT_SCORE"),
                                                $("after")
                                                        .get("CREDIT_UTILIZATION")
                                                        .as("CREDIT_UTILIZATION"),
                                                $("after")
                                                        .get("OPEN_CREDIT_ACCOUNTS")
                                                        .as("OPEN_CREDIT_ACCOUNTS"),
                                                $("after")
                                                        .get("PUBLIC_RECORDS")
                                                        .as("PUBLIC_RECORDS")))
                        .where($("applicant_id").isEqual($("credit_applicant_id")))
                        .select(
                                $("application_id"),
                                $("customer_email"),
                                $("customer_name").as("borrower_name"),
                                $("applicant_id"),
                                $("income"),
                                $("payslips"),
                                $("loan_amount"),
                                $("property_address"),
                                $("property_state"),
                                $("property_value"),
                                $("employment_status"),
                                $("CREDIT_SCORE").as("credit_score"),
                                $("CREDIT_UTILIZATION").as("credit_utilization"),
                                $("OPEN_CREDIT_ACCOUNTS").as("open_credit_accounts"),
                                $("PUBLIC_RECORDS").as("recent_defaults"),
                                $("loan_amount")
                                        .cast(DataTypes.DECIMAL(10, 2))
                                        .dividedBy($("income").cast(DataTypes.DECIMAL(10, 2)))
                                        .times(100)
                                        .round(2)
                                        .as("debt_to_income_ratio"),
                                $("application_ts").as("application_ts"));

        // Insert the results into the created table
        enrichedApplications.executeInsert(ENRICHED_MORTGAGE_TABLE);
    }
}
