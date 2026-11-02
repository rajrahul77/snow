Apache Iceberg Tables
​Apache Iceberg tables allow Snowflake to query and modify data stored in open Parquet format on external cloud object storage.
​These tables use the Apache Iceberg open table specification to maintain transactional consistency, schema evolution, and partition metadata.
​Snowflake supports full read and write operations, partitioned writes, row-level deletes, and Time Travel on Iceberg tables.
​Organizations can store data in their own cloud buckets while still leveraging Snowflake's query engine and governance controls.
​This approach eliminates data duplication and prevents vendor lock-in across multi-engine data lakehouse architectures.
​Dynamic Iceberg Tables
​Dynamic Iceberg tables combine Snowflake's declarative streaming pipeline automation with the open Apache Iceberg storage format.
​Instead of writing complex task and stream orchestration, users define the target table using a standard SQL transformation query.
​Snowflake automatically refreshes the underlying Parquet files in external cloud storage based on a defined target lag interval.
​Incremental changes from base tables are processed continuously, reducing compute overhead compared to full table rebuilds.
​External query engines can immediately read the updated Iceberg tables without requiring separate data export pipelines.
​Catalog-Linked Databases
​Catalog-linked databases connect Snowflake directly to external Iceberg REST catalogs such as AWS Glue or Apache Polaris.
​Once linked, Snowflake automatically discovers and synchronizes namespaces and Iceberg tables registered in the external catalog.
​Users can query and write to externally managed tables without manually creating or refreshing individual table definitions in Snowflake.
​Access control policies and governance rules applied in Snowflake remain enforced across all catalog-linked objects.
​This capability enables real-time interoperability between Snowflake and external compute engines sharing a unified lakehouse catalog.
​Hybrid Tables
​Hybrid tables bring transactional (OLTP) and analytical (OLAP) workloads together within a single unified Snowflake platform.
​Unlike standard column-oriented micro-partitions, hybrid tables utilize a row-oriented datastore optimized for single-row operations.
​They enforce primary key uniqueness, foreign key referential integrity, and secondary indexes to accelerate point lookups.
​Row-level locking allows high-concurrency inserts, updates, and deletes with single-digit millisecond latency.
​Hybrid tables can be joined directly with standard analytical tables in the same SQL query without moving data across systems.
​Search Optimization Service
​Search Optimization Service accelerates selective point-lookup queries on large tables containing billions of rows.
​It maintains a persistent, serverless search access path that tracks which micro-partitions contain specific column values.
​When a query filters on equality, substrings, regular expressions, geospatial data, or VARIANT columns, Snowflake checks this access path first.
​Micro-partitions that do not contain matching values are skipped immediately, avoiding unnecessary table scans.
​Unlike data clustering, which sorts data along one key path, search optimization accelerates lookups across multiple independent columns simultaneously.
​Gen2 Standard Warehouses
​Gen2 Standard Warehouses represent an upgraded compute architecture engineered for faster analytical and data engineering workloads.
​They incorporate newer hardware generations and vectorized execution enhancements to accelerate core SQL operations.
​Table scans, joins, aggregations, and data manipulation operations such as updates, deletes, and merges run more than twice as fast.
​Workloads transition to Gen2 warehouses seamlessly without requiring changes to existing SQL queries or table structures.
​Faster query completion reduces overall warehouse active time, improving throughput for concurrent user workloads.
​Adaptive Compute
​Adaptive Compute is an autonomous, workload-aware compute engine that eliminates manual virtual warehouse sizing and tuning.
​Instead of selecting fixed warehouse sizes or configuring multi-cluster limits, users define high-level performance and cost objectives.
​Snowflake dynamically provisions, scales, and suspends compute resources in real time based on incoming query complexity and concurrency.
​Queries are automatically routed to appropriately sized compute clusters to prevent resource contention and queuing delays.
​This automated resource management optimizes credit consumption while maintaining consistent query response times.
​Snowflake Openflow
​Snowflake Openflow is a fully managed, multi-cloud data integration service built on Apache NiFi for end-to-end data movement.
​It provides hundreds of prebuilt connectors to ingest structured and unstructured data from databases, SaaS applications, and streaming systems.
​Openflow supports high-speed Change Data Capture (CDC), replicating source database transactions into Snowflake in near real time.
​Data engineers can visually design, monitor, and scale complex ingestion and routing pipelines within a centralized interface.
​Because Openflow integrates directly with Snowflake governance, ingested data inherits security and lineage tracking upon arrival.
​Snowpipe Streaming
​Snowpipe Streaming ingests continuous row-level data streams directly into Snowflake tables without staging intermediate files.
​Client applications write rows through the Snowflake Ingest SDK or Kafka connector straight into target tables.
​Its high-performance architecture achieves ultra-low-latency data availability, making streaming records queryable within seconds.
​By bypassing file creation and cloud storage staging, Snowpipe Streaming lowers both ingestion latency and operational cost.
​It natively supports ordered row delivery and seamless integration with Dynamic Tables for real-time analytical pipelines.
​Workspaces and dbt Projects
​Workspaces provide a unified, Git-integrated development environment directly inside the Snowsight user interface.
​Data teams can author, version-control, test, and execute native dbt projects within Snowflake without external hosting infrastructure.
​Changes can be committed to branches, reviewed via pull requests, and deployed to production environments from a single workspace.
​Native orchestration schedules dbt model runs alongside Snowflake Tasks and Dynamic Tables using built-in compute warehouses.
​Centralizing transformation code inside Snowflake simplifies security boundaries and removes third-party orchestration overhead.
​Aggregation Policy
​An aggregation policy is a schema-level privacy control that prevents users from viewing individual row-level records in a table.
​Queries executed against an aggregation-protected table must aggregate data using functions such as COUNT, SUM, or AVG.
​Administrators define a minimum group size threshold, ensuring every returned aggregation group contains at least that many rows.
​If a query filter isolates fewer rows than the required minimum threshold, Snowflake blocks or combines the results to protect individual privacy.
​This enables secure analytics on sensitive customer or partner datasets without exposing personally identifiable records.
​Projection Policy
​A projection policy is a column-level security feature that prevents users from directly selecting sensitive column values.
​When a projection policy is applied, queries cannot include the protected column in the outermost SELECT projection list.
​However, authorized users can still reference the protected column inside WHERE filters, JOIN conditions, or GROUP BY clauses.
​This allows analysts to join tables on sensitive identifiers like email addresses or tax IDs without ever viewing the raw values.
​Projection policies can be attached directly to columns or dynamically assigned across tables using classification tags.
​Data Metric Functions
​Data Metric Functions (DMFs) provide automated, serverless data quality monitoring across Snowflake tables and views.
​Snowflake includes built-in system metrics to measure data freshness, row volume, null counts, blank values, and duplicate records.
​Users can also define custom SQL data metric functions to validate complex business rules and referential relationships.
​Data quality expectations allow teams to set threshold rules on metrics and trigger automated alerts when violations occur.
​All quality measurements are logged in an event table, providing historical visibility into pipeline reliability and table health.
​Horizon Catalog and Process Lineage
​Horizon Catalog is Snowflake's built-in governance solution providing unified discovery, security, and compliance across data assets.
​It automatically classifies sensitive data, applies privacy tags, and enforces access policies across internal and Iceberg tables.
​Process Lineage extends table traceability by mapping how data flows through streams, tasks, dynamic tables, and stored procedures.
​Administrators can visually trace upstream data sources and evaluate the downstream impact of schema changes before deployment.
​Unified audit logs and lineage graphs simplify regulatory compliance and accelerate root-cause analysis when data anomalies arise.
​WORM Backups
​Write-Once-Read-Many (WORM) Backups provide immutable data protection against ransomware, accidental deletion, and malicious tampering.
​Once a backup snapshot is created with a retention lock, it cannot be modified, overwritten, or deleted before its expiration date.
​Even account administrators and privileged system users are prevented from shortening the retention period or destroying locked backups.
​Backup Policies automate snapshot creation and expiration schedules across databases, schemas, and critical tables.
​This capability complements Time Travel and Fail-safe by satisfying strict regulatory requirements for long-term immutable storage.
​AISQL and Automated PII Redaction
​AISQL embeds multimodal large language model capabilities directly into standard Snowflake SQL syntax for scalable AI processing.
​Analysts can filter, join, classify, and summarize unstructured text, images, audio files, and PDF documents using native SQL functions.
​Document and audio functions automatically extract structured tables from PDFs and transcribe spoken recordings into queryable text.
​The AI redaction function automatically detects and masks unstructured personally identifiable information within free-text columns.
​Processing unstructured data directly inside the warehouse eliminates the need to export sensitive files to external AI services.
​Snowflake Cortex Code and Semantic Views
​Snowflake Cortex Code (CoCo) is a context-aware AI agent that assists with data engineering, SQL optimization, and governance tasks.
​It understands your account's metadata and schema structure to automatically generate pipelines, dbt models, and security policies.
​Semantic Views define a governed layer of business metrics, dimensions, and table relationships directly inside the database.
​Semantic View Autopilot analyzes historical query patterns to automatically create and maintain these semantic definitions.
​Both business intelligence tools and conversational AI agents use Semantic Views to deliver consistent, accurate answers from enterprise data.