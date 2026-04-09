package com.confluent.datagen;

import com.github.javafaker.Faker;
import io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient;
import io.confluent.kafka.schemaregistry.client.SchemaMetadata;
import io.confluent.kafka.schemaregistry.client.SchemaRegistryClient;
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericData;
import org.apache.avro.generic.GenericRecord;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.*;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.atomic.AtomicInteger;

public class DataGenerator {

    private static final Logger log = LoggerFactory.getLogger(DataGenerator.class);
    private static final Faker faker = new Faker();
    private static final Random random = new Random();

    // Sequential ID counters
    private static final AtomicInteger txIdCounter = new AtomicInteger(3000000);

    // In-memory applicant cache (preloaded from Postgres to avoid per-event DB queries)
    // Using CopyOnWriteArrayList for thread-safe reads/writes across Stage 3 threads
    private static List<Map<String, Object>> highCreditApplicants = new java.util.concurrent.CopyOnWriteArrayList<>();
    private static List<Map<String, Object>> mediumCreditApplicants = new java.util.concurrent.CopyOnWriteArrayList<>();
    private static List<Map<String, Object>> lowCreditApplicants = new java.util.concurrent.CopyOnWriteArrayList<>();
    private static List<Map<String, Object>> allApplicants = new java.util.concurrent.CopyOnWriteArrayList<>();

    // Environment variables
    private static final String KAFKA_BOOTSTRAP_SERVERS = env("KAFKA_BOOTSTRAP_SERVERS");
    private static final String KAFKA_API_KEY = env("KAFKA_API_KEY");
    private static final String KAFKA_API_SECRET = env("KAFKA_API_SECRET");
    private static final String SCHEMA_REGISTRY_URL = env("SCHEMA_REGISTRY_URL");
    private static final String SCHEMA_REGISTRY_API_KEY = env("SCHEMA_REGISTRY_API_KEY");
    private static final String SCHEMA_REGISTRY_API_SECRET = env("SCHEMA_REGISTRY_API_SECRET");
    private static final String PG_HOST = env("PG_HOST");
    private static final String PG_PORT = env("PG_PORT");
    private static final String PG_DATABASE = env("PG_DATABASE");
    private static final String PG_USERNAME = env("PG_USERNAME");
    private static final String PG_PASSWORD = env("PG_PASSWORD");

    // Configurable mortgage application parameters
    private static final int MORTGAGE_APP_INTERVAL_SECONDS = envOrDefault("MORTGAGE_APP_INTERVAL_SECONDS", 600);
    private static final int MORTGAGE_APP_COUNT = envOrDefault("MORTGAGE_APP_COUNT", 20);
    private static final int MORTGAGE_APP_STARTUP_DELAY_SECONDS = envOrDefault("MORTGAGE_APP_STARTUP_DELAY_SECONDS", 0);
    private static final int CDC_HEARTBEAT_INTERVAL_SECONDS = envOrDefault("CDC_HEARTBEAT_INTERVAL_SECONDS", 10);

    // Topics
    private static final String TOPIC_MORTGAGE_APPLICATIONS = "mortgage_applications";
    private static final String TOPIC_PAYMENT_HISTORY = "payment_history";

    public static void main(String[] args) {
        log.info("=== Data Generator Starting ===");

        try {
            log.info("--- Stage 1: Seeding credit scores to Postgres ---");
            stage1_seedCreditScores();

            log.info("--- Stage 2: Generating historical payments to Kafka ---");
            stage2_historicalPayments();

            log.info("--- Stage 3: Continuous stream (mortgage apps + payments) ---");
            stage3_continuousStream();
        } catch (Exception e) {
            log.error("Data generation failed", e);
            System.exit(1);
        }
    }

    // ========================================================================
    // Stage 1: Seed Postgres with 702 credit score rows
    // ========================================================================

    private static void stage1_seedCreditScores() throws Exception {
        try (Connection conn = getPostgresConnection()) {
            // Create table if not exists (replicates ShadowTraffic tablePolicy: "create")
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("""
                    CREATE TABLE IF NOT EXISTS applicant_credit_score (
                        applicant_id VARCHAR(255) PRIMARY KEY,
                        applicant_name VARCHAR(255),
                        credit_score INT,
                        credit_utilization DECIMAL(5,1),
                        open_credit_accounts INT,
                        total_credit_limit INT,
                        public_records INT,
                        updated_at TIMESTAMP DEFAULT NOW()
                    )
                    """);
            }

            String insertSql = """
                INSERT INTO applicant_credit_score
                    (applicant_id, applicant_name, credit_score, credit_utilization,
                     open_credit_accounts, total_credit_limit, public_records)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (applicant_id) DO NOTHING
                """;

            conn.setAutoCommit(false);
            try (PreparedStatement ps = conn.prepareStatement(insertSql)) {
                // High credit scores: 100 rows
                seedCreditScores(ps, 100, 750, 850, 0, 100, () -> 0);
                log.info("  Batched 100 high credit score rows");

                // Medium credit scores: 500 rows
                seedCreditScores(ps, 500, 501, 750, 0, 100,
                    () -> weightedChoice(Map.of(0, 9, 1, 1)));
                log.info("  Batched 500 medium credit score rows");

                // Low credit scores: 100 rows
                seedCreditScores(ps, 100, 300, 500, 0, 100,
                    () -> weightedChoice(Map.of(0, 1, 1, 1, 2, 2, 3, 3, 4, 3)));
                log.info("  Batched 100 low credit score rows");

                // Sample high credit applicant: John Doe
                addCreditScoreBatch(ps, "C-100000", "John Doe",
                    randomInt(800, 850),
                    randomDecimal(0, 20, 1),
                    randomInt(0, 5),
                    randomInt(1000, 50000),
                    0);
                log.info("  Batched sample high credit applicant: John Doe (C-100000)");

                // Sample low credit applicant: Omar Soli
                addCreditScoreBatch(ps, "C-200000", "Omar Soli",
                    randomInt(300, 350),
                    randomDecimal(90, 100, 1),
                    randomInt(0, 5),
                    randomInt(1000, 50000),
                    5);
                log.info("  Batched sample low credit applicant: Omar Soli (C-200000)");

                ps.executeBatch();
                conn.commit();
            }
        }
        log.info("Stage 1 complete: 702 credit score rows seeded");
    }

    private static void seedCreditScores(PreparedStatement ps, int count,
                                          int scoreMin, int scoreMax,
                                          int utilizationMin, int utilizationMax,
                                          java.util.function.IntSupplier publicRecordsSupplier) throws SQLException {
        for (int i = 0; i < count; i++) {
            addCreditScoreBatch(ps,
                UUID.randomUUID().toString(),
                faker.name().fullName(),
                randomInt(scoreMin, scoreMax),
                randomDecimal(utilizationMin, utilizationMax, 1),
                randomInt(0, 5),
                randomInt(1000, 50000),
                publicRecordsSupplier.getAsInt());
        }
    }

    private static void addCreditScoreBatch(PreparedStatement ps, String applicantId,
                                             String name, int score, double utilization,
                                             int openAccounts, int totalLimit,
                                             int publicRecords) throws SQLException {
        ps.setString(1, applicantId);
        ps.setString(2, name);
        ps.setInt(3, score);
        ps.setBigDecimal(4, BigDecimal.valueOf(utilization));
        ps.setInt(5, openAccounts);
        ps.setInt(6, totalLimit);
        ps.setInt(7, publicRecords);
        ps.addBatch();
    }

    // ========================================================================
    // Stage 2: Historical payments (700 events, no throttle)
    // ========================================================================

    private static void stage2_historicalPayments() throws Exception {
        Schema schema = getSchema(TOPIC_PAYMENT_HISTORY + "-value");

        // Preload applicants into memory to avoid 700 individual DB queries
        try (Connection conn = getPostgresConnection()) {
            preloadApplicants(conn);
        }

        try (KafkaProducer<String, GenericRecord> producer = createProducer()) {
            // Guaranteed successful payment for John Doe
            GenericRecord johnDoePayment = new GenericData.Record(schema);
            johnDoePayment.put("transaction_id", "TX-" + txIdCounter.getAndIncrement());
            johnDoePayment.put("applicant_id", "C-100000");
            johnDoePayment.put("method", "auto-debit");
            johnDoePayment.put("status", "successful");
            johnDoePayment.put("failure_reason", "N/A");
            johnDoePayment.put("amount", 300L);
            long dateMs = Instant.now().toEpochMilli() - ThreadLocalRandom.current().nextLong(0, 31560192000L);
            LocalDate date = Instant.ofEpochMilli(dateMs).atZone(ZoneId.systemDefault()).toLocalDate();
            johnDoePayment.put("payment_date", date.format(DateTimeFormatter.ofPattern("yyyy-MM-dd")));
            producer.send(new ProducerRecord<>(TOPIC_PAYMENT_HISTORY,
                johnDoePayment.get("transaction_id").toString(), johnDoePayment));
            log.info("  Sent guaranteed payment for John Doe (C-100000)");

            for (int i = 0; i < 700; i++) {
                // Random time offset: 0 to ~365 days in the past
                long timeOffset = ThreadLocalRandom.current().nextLong(0, 31560192000L);
                GenericRecord record = buildPaymentRecord(schema, null, timeOffset);
                String txId = record.get("transaction_id").toString();
                producer.send(new ProducerRecord<>(TOPIC_PAYMENT_HISTORY, txId, record));

                if ((i + 1) % 100 == 0) {
                    producer.flush();
                    log.info("  Sent {} / 700 historical payments", i + 1);
                }
            }
            producer.flush();
        }
        log.info("Stage 2 complete: 701 historical payments sent (including John Doe)");
    }

    // ========================================================================
    // Stage 3: Continuous stream (parallel threads)
    // ========================================================================

    private static void stage3_continuousStream() throws Exception {
        Schema mortgageSchema = getSchema(TOPIC_MORTGAGE_APPLICATIONS + "-value");
        Schema paymentSchema = getSchema(TOPIC_PAYMENT_HISTORY + "-value");

        // Thread 1: Mortgage applications (configurable count and interval)
        Thread mortgageThread = new Thread(() -> {
            try (KafkaProducer<String, GenericRecord> producer = createProducer()) {
                log.info("  Mortgage application thread waiting {} seconds before starting...",
                    MORTGAGE_APP_STARTUP_DELAY_SECONDS);
                Thread.sleep(MORTGAGE_APP_STARTUP_DELAY_SECONDS * 1000L);

                boolean continuous = MORTGAGE_APP_COUNT == -1;
                String totalLabel = continuous ? "unlimited" : String.valueOf(MORTGAGE_APP_COUNT);
                log.info("  Mortgage application thread started (count={}, interval={}s)",
                    totalLabel, MORTGAGE_APP_INTERVAL_SECONDS);

                int i = 0;
                while (continuous || i < MORTGAGE_APP_COUNT) {
                    GenericRecord record = buildMortgageRecord(mortgageSchema, null, i);
                    String key = record.get("customer_email").toString();
                    try {
                        producer.send(new ProducerRecord<>(TOPIC_MORTGAGE_APPLICATIONS, key, record));
                        producer.flush();
                        log.info("  Mortgage application {} / {} sent (app_id={})",
                            i + 1, totalLabel, record.get("application_id"));
                    } catch (org.apache.kafka.common.errors.SerializationException e) {
                        log.info("  Mortgage application {} / {} routed to DLQ (app_id={}, payslips={})",
                            i + 1, totalLabel, record.get("application_id"), record.get("payslips"));
                    }
                    i++;

                    Thread.sleep(MORTGAGE_APP_INTERVAL_SECONDS * 1000L);
                }
                log.info("  Mortgage application thread finished ({} events)", MORTGAGE_APP_COUNT);
            } catch (InterruptedException e) {
                log.info("Mortgage application thread interrupted, shutting down");
            } catch (Exception e) {
                log.error("Mortgage application thread failed", e);
            }
        }, "mortgage-thread");

        // Thread 2: Payment history (continuous, 5-10s throttle)
        Thread paymentThread = new Thread(() -> {
            try (KafkaProducer<String, GenericRecord> producer = createProducer()) {
                int count = 0;
                while (!Thread.currentThread().isInterrupted()) {
                    // time_offset = 0 for stage 3 (current date)
                    GenericRecord record = buildPaymentRecord(paymentSchema, null, 0);
                    String txId = record.get("transaction_id").toString();
                    producer.send(new ProducerRecord<>(TOPIC_PAYMENT_HISTORY, txId, record));
                    producer.flush();
                    count++;
                    log.info("  Payment {} sent (tx_id={})", count, txId);

                    long throttle = randomInt(5000, 10000);
                    Thread.sleep(throttle);
                }
            } catch (InterruptedException e) {
                log.info("Payment thread interrupted, shutting down");
            } catch (Exception e) {
                log.error("Payment thread failed", e);
            }
        }, "payment-thread");

        // Thread 3: CDC heartbeat — periodic UPDATE to advance CDC topic watermark
        Thread heartbeatThread = null;
        if (CDC_HEARTBEAT_INTERVAL_SECONDS > 0) {
            heartbeatThread = new Thread(() -> {
                try (Connection conn = getPostgresConnection()) {
                    String updateSql = "UPDATE applicant_credit_score SET updated_at = NOW() WHERE applicant_id = ?";
                    int count = 0;
                    while (!Thread.currentThread().isInterrupted()) {
                        // Pick a random applicant from the in-memory cache
                        Map<String, Object> applicant = allApplicants.get(random.nextInt(allApplicants.size()));
                        String applicantId = (String) applicant.get("applicant_id");
                        try (PreparedStatement ps = conn.prepareStatement(updateSql)) {
                            ps.setString(1, applicantId);
                            ps.executeUpdate();
                        }
                        count++;
                        if (count % 100 == 0) {
                            log.info("  CDC heartbeat: {} updates sent", count);
                        }
                        // Random sleep between 5-10 seconds
                        Thread.sleep((long) (Math.random() * 5000 + 5000));
                    }
                } catch (InterruptedException e) {
                    log.info("Heartbeat thread interrupted, shutting down");
                } catch (Exception e) {
                    log.error("Heartbeat thread failed", e);
                }
            }, "heartbeat-thread");
        }

        mortgageThread.start();
        paymentThread.start();
        if (heartbeatThread != null) {
            heartbeatThread.start();
            log.info("CDC heartbeat thread started (interval=random 5-10s)");
        }

        // Wait for threads (payment thread runs indefinitely)
        mortgageThread.join();
        log.info("Mortgage thread finished. Payment thread continues running. Press Ctrl+C to stop.");
        paymentThread.join();
        if (heartbeatThread != null) heartbeatThread.join();
    }

    // ========================================================================
    // Record builders
    // ========================================================================

    private static GenericRecord buildMortgageRecord(Schema schema, Connection conn, int eventIndex) throws SQLException {
        // Lookup random existing applicant from Postgres
        Map<String, Object> applicant = lookupRandomApplicant(conn, null, null);

        GenericRecord record = new GenericData.Record(schema);

        // application_id: unique UUID to avoid collisions on container restart
        record.put("application_id", "APP-" + UUID.randomUUID().toString());

        // customer_email: Faker email
        record.put("customer_email", faker.internet().emailAddress());

        // customer_name: from PG lookup
        record.put("customer_name", applicant.get("applicant_name"));

        // applicant_id: 999/1000 from PG lookup, 1/1000 = "-1"
        String applicantId = weightedChoice(Map.of(0, 999, 1, 1)) == 0
            ? (String) applicant.get("applicant_id")
            : "-1";
        record.put("applicant_id", applicantId);

        // property_value: weighted 1→[100K-500K], 13→[1M-1.5M]
        long propertyValue = weightedChoice(Map.of(0, 1, 1, 13)) == 0
            ? randomInt(100000, 500000)
            : randomInt(1000000, 1500000);
        record.put("property_value", propertyValue);

        // loan_amount: uniform [100K-1.5M], clamped to 75% of property_value
        long loanAmount = randomInt(100000, 1500000);
        long maxLoan = (long) (propertyValue * 0.75);
        loanAmount = Math.min(loanAmount, maxLoan);
        record.put("loan_amount", loanAmount);

        // income: weighted 9→[loan*0.25, loan*0.25*12], 1→[loan*0.25/8, loan*0.25]
        long income;
        double loanQuarter = loanAmount * 0.25;
        if (weightedChoice(Map.of(0, 9, 1, 1)) == 0) {
            income = randomLong((long) loanQuarter, (long) (loanQuarter * 12));
        } else {
            income = randomLong((long) (loanQuarter / 8), (long) loanQuarter);
        }
        record.put("income", income);

        // property_address: Faker street address
        record.put("property_address", faker.address().streetAddress());

        // property_state: weighted 3→random, 3→California, 2→New York, 2→Texas, 1→Florida
        int stateChoice = weightedChoice(Map.of(0, 3, 1, 3, 2, 2, 3, 2, 4, 1));
        String state = switch (stateChoice) {
            case 0 -> faker.address().state();
            case 1 -> "California";
            case 2 -> "New York";
            case 3 -> "Texas";
            case 4 -> "Florida";
            default -> faker.address().state();
        };
        record.put("property_state", state);

        // payslips: first 3 are always "N/A" (for demo), then 9/10 valid, 1/10 "N/A" (triggers DLQ)
        String payslips;
        if (eventIndex < 3) {
            payslips = "N/A";
        } else {
            payslips = weightedChoice(Map.of(0, 9, 1, 1)) == 0
                ? "s3://riverbank-payslip-bucket/" + applicantId
                : "N/A";
        }
        record.put("payslips", payslips);

        // employment_status: 4→Full-employed, 1→self-employed
        String employmentStatus = weightedChoice(Map.of(0, 4, 1, 1)) == 0
            ? "Full-employed"
            : "self-employed";
        record.put("employment_status", employmentStatus);

        // application_ts: current timestamp millis
        record.put("application_ts", Instant.now().toEpochMilli());

        return record;
    }

    private static GenericRecord buildPaymentRecord(Schema schema, Connection conn,
                                                     long timeOffset) throws SQLException {
        // Weighted tier selection (total weight 602)
        int tier = weightedChoice(Map.of(0, 200, 1, 1, 2, 200, 3, 200, 4, 1));

        Map<String, Object> applicant;
        String status;
        String failureReason;

        switch (tier) {
            case 0 -> {
                // High credit (weight 200): score >= 750, 100% success
                applicant = lookupRandomApplicant(conn, 750, null);
                status = "successful";
                failureReason = "N/A";
            }
            case 1 -> {
                // John Doe (weight 1): fixed ID, 100% success
                applicant = lookupApplicantById(conn, "C-100000");
                status = "successful";
                failureReason = "N/A";
            }
            case 2 -> {
                // Medium credit (weight 200): score 501-750, 90% success / 10% failure
                applicant = lookupRandomApplicant(conn, 501, 750);
                if (weightedChoice(Map.of(0, 9, 1, 1)) == 0) {
                    status = "successful";
                    failureReason = "N/A";
                } else {
                    status = "failed";
                    failureReason = "insufficient_funds";
                }
            }
            case 3 -> {
                // Low credit (weight 200): score <= 500, 20% success / 80% failure
                applicant = lookupRandomApplicant(conn, null, 500);
                if (weightedChoice(Map.of(0, 2, 1, 8)) == 0) {
                    status = "successful";
                    failureReason = "N/A";
                } else {
                    status = "failed";
                    failureReason = "insufficient_funds";
                }
            }
            case 4 -> {
                // Omar Soli (weight 1): fixed ID, 20% success / 80% failure
                applicant = lookupApplicantById(conn, "C-200000");
                if (weightedChoice(Map.of(0, 2, 1, 8)) == 0) {
                    status = "successful";
                    failureReason = "N/A";
                } else {
                    status = "failed";
                    failureReason = "insufficient_funds";
                }
            }
            default -> throw new IllegalStateException("Unexpected tier: " + tier);
        }

        GenericRecord record = new GenericData.Record(schema);
        record.put("transaction_id", "TX-" + txIdCounter.getAndIncrement());
        record.put("applicant_id", applicant.get("applicant_id"));
        record.put("method", "auto-debit");
        record.put("status", status);
        record.put("failure_reason", failureReason);
        record.put("amount", (long) randomInt(100, 500));

        // Payment date: now - time_offset
        long dateMs = Instant.now().toEpochMilli() - timeOffset;
        LocalDate date = Instant.ofEpochMilli(dateMs).atZone(ZoneId.systemDefault()).toLocalDate();
        record.put("payment_date", date.format(DateTimeFormatter.ofPattern("yyyy-MM-dd")));

        return record;
    }

    // ========================================================================
    // Postgres helpers
    // ========================================================================

    private static Connection getPostgresConnection() throws SQLException {
        String url = String.format("jdbc:postgresql://%s:%s/%s", PG_HOST, PG_PORT, PG_DATABASE);
        return DriverManager.getConnection(url, PG_USERNAME, PG_PASSWORD);
    }

    /**
     * Preload all applicants from Postgres into memory, grouped by credit tier.
     * This avoids per-event DB queries in stages 2 and 3.
     */
    private static void preloadApplicants(Connection conn) throws SQLException {
        highCreditApplicants.clear();
        mediumCreditApplicants.clear();
        lowCreditApplicants.clear();
        allApplicants.clear();

        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(
                 "SELECT applicant_id, applicant_name, credit_score FROM applicant_credit_score")) {
            while (rs.next()) {
                Map<String, Object> applicant = Map.of(
                    "applicant_id", rs.getString("applicant_id"),
                    "applicant_name", rs.getString("applicant_name")
                );
                int score = rs.getInt("credit_score");
                allApplicants.add(applicant);
                if (score >= 750) highCreditApplicants.add(applicant);
                else if (score >= 501) mediumCreditApplicants.add(applicant);
                else lowCreditApplicants.add(applicant);
            }
        }
        log.info("  Preloaded {} applicants (high={}, medium={}, low={})",
            allApplicants.size(), highCreditApplicants.size(),
            mediumCreditApplicants.size(), lowCreditApplicants.size());
    }

    /** Pick a random applicant from the given cached list. */
    private static Map<String, Object> randomFromList(List<Map<String, Object>> list) {
        return list.get(random.nextInt(list.size()));
    }

    /**
     * Lookup a random applicant by credit score range from the in-memory cache.
     * Falls back to DB query if cache is empty (stage 3 mortgage apps use conn).
     */
    private static Map<String, Object> lookupRandomApplicant(Connection conn,
                                                              Integer minScore,
                                                              Integer maxScore) throws SQLException {
        // Use cached lists if available
        if (!allApplicants.isEmpty()) {
            if (minScore != null && minScore >= 750) return randomFromList(highCreditApplicants);
            if (minScore != null && minScore >= 501 && maxScore != null && maxScore <= 750) return randomFromList(mediumCreditApplicants);
            if (maxScore != null && maxScore <= 500) return randomFromList(lowCreditApplicants);
            return randomFromList(allApplicants);
        }

        // Fallback to DB query
        StringBuilder sql = new StringBuilder(
            "SELECT applicant_id, applicant_name FROM applicant_credit_score WHERE 1=1");
        if (minScore != null) sql.append(" AND credit_score >= ").append(minScore);
        if (maxScore != null) sql.append(" AND credit_score <= ").append(maxScore);
        sql.append(" ORDER BY RANDOM() LIMIT 1");

        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql.toString())) {
            if (rs.next()) {
                return Map.of(
                    "applicant_id", rs.getString("applicant_id"),
                    "applicant_name", rs.getString("applicant_name")
                );
            }
        }
        throw new IllegalStateException("No applicant found for score range ["
            + minScore + ", " + maxScore + "]");
    }

    private static Map<String, Object> lookupApplicantById(Connection conn,
                                                            String applicantId) throws SQLException {
        // Check cache first
        for (Map<String, Object> a : allApplicants) {
            if (applicantId.equals(a.get("applicant_id"))) return a;
        }

        // Fallback to DB
        if (conn != null) {
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT applicant_id, applicant_name FROM applicant_credit_score WHERE applicant_id = ?")) {
                ps.setString(1, applicantId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        return Map.of(
                            "applicant_id", rs.getString("applicant_id"),
                            "applicant_name", rs.getString("applicant_name")
                        );
                    }
                }
            }
        }
        throw new IllegalStateException("Applicant not found: " + applicantId);
    }

    // ========================================================================
    // Kafka helpers
    // ========================================================================

    private static KafkaProducer<String, GenericRecord> createProducer() {
        Properties props = new Properties();

        // Connection & auth
        props.put("bootstrap.servers", KAFKA_BOOTSTRAP_SERVERS);
        props.put("security.protocol", "SASL_SSL");
        props.put("sasl.mechanism", "PLAIN");
        props.put("sasl.jaas.config",
            "org.apache.kafka.common.security.plain.PlainLoginModule required username='"
            + KAFKA_API_KEY + "' password='" + KAFKA_API_SECRET + "';");

        // Serializers
        props.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        props.put("value.serializer", "io.confluent.kafka.serializers.KafkaAvroSerializer");

        // Batching — accumulate records before sending to reduce network round trips
        props.put("linger.ms", "100");
        props.put("batch.size", "65536");

        // Schema Registry
        props.put("schema.registry.url", SCHEMA_REGISTRY_URL);
        props.put("basic.auth.credentials.source", "USER_INFO");
        props.put("basic.auth.user.info", SCHEMA_REGISTRY_API_KEY + ":" + SCHEMA_REGISTRY_API_SECRET);

        // Data contracts — fetch latest schema (with rules) from SR, don't auto-register
        props.put("auto.register.schemas", "false");
        props.put("use.latest.version", "true");

        // Use legacy payload-prefix wire format (magic byte 0x00 + 4-byte schema ID)
        // instead of header-based schema ID, for compatibility with Flink consumers
        props.put("value.schema.id.serializer", "io.confluent.kafka.serializers.schema.id.PrefixSchemaIdSerializer");

        return new KafkaProducer<>(props);
    }

    private static Schema getSchema(String subject) throws Exception {
        Map<String, String> srConfig = Map.of(
            "schema.registry.url", SCHEMA_REGISTRY_URL,
            "basic.auth.credentials.source", "USER_INFO",
            "basic.auth.user.info", SCHEMA_REGISTRY_API_KEY + ":" + SCHEMA_REGISTRY_API_SECRET
        );
        SchemaRegistryClient client = new CachedSchemaRegistryClient(
            SCHEMA_REGISTRY_URL, 100,
            List.of(new io.confluent.kafka.schemaregistry.avro.AvroSchemaProvider()),
            srConfig);
        SchemaMetadata meta = client.getLatestSchemaMetadata(subject);
        return new Schema.Parser().parse(meta.getSchema());
    }

    // ========================================================================
    // Utility methods
    // ========================================================================

    private static String env(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Missing required environment variable: " + name);
        }
        return value;
    }

    private static int envOrDefault(String name, int defaultValue) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        return Integer.parseInt(value);
    }

    private static int randomInt(int min, int max) {
        return ThreadLocalRandom.current().nextInt(min, max + 1);
    }

    private static long randomLong(long min, long max) {
        if (min >= max) return min;
        return ThreadLocalRandom.current().nextLong(min, max + 1);
    }

    private static double randomDecimal(int min, int max, int decimals) {
        double value = min + (max - min) * random.nextDouble();
        return BigDecimal.valueOf(value)
            .setScale(decimals, RoundingMode.HALF_UP)
            .doubleValue();
    }

    /**
     * Weighted random choice. Returns the key selected based on weights.
     * Example: Map.of(0, 9, 1, 1) → returns 0 with 90% probability, 1 with 10%.
     */
    private static int weightedChoice(Map<Integer, Integer> weights) {
        int totalWeight = weights.values().stream().mapToInt(Integer::intValue).sum();
        int roll = random.nextInt(totalWeight);
        int cumulative = 0;
        for (Map.Entry<Integer, Integer> entry : weights.entrySet()) {
            cumulative += entry.getValue();
            if (roll < cumulative) {
                return entry.getKey();
            }
        }
        // Should not reach here
        return weights.keySet().iterator().next();
    }
}
