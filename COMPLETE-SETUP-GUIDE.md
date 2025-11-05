# Complete Datastream Setup Guide - Official Steps

## **Simple Explanation First**

### **What We're Building:**
```
Aurora DB (AWS) ──> Datastream (Google) ──> BigQuery (Google)
   Live data          Copier service        Analytics database
```

**In plain English:**
- Your app saves data to **Aurora** (AWS PostgreSQL database)
- **Datastream** watches Aurora and copies every change in real-time
- Changes appear in **BigQuery** (Google's analytics database) within seconds
- You can run massive reports in BigQuery without slowing down Aurora!

---

## **STEP-BY-STEP SETUP**

### **PHASE 1: Configure Aurora PostgreSQL (AWS Side)**

#### **Step 1.1: Create Parameter Group**

**From AWS Console:**
1. Go to RDS Dashboard → Parameter Groups
2. Click "Create Parameter Group"
3. Fill in:
   - **Parameter group family:** `aurora-postgresql15` (match your version)
   - **Type:** `DB Cluster Parameter Group`
   - **Group name:** `datastream-replication-params`
   - **Description:** `Enable logical replication for Datastream`
4. Click "Create"

#### **Step 1.2: Enable Logical Replication**

1. Select your new parameter group
2. Click "Edit" under Parameter group actions
3. Search for `rds.logical_replication`
4. Change value from `0` to `1`
5. Click "Save Changes"

**Or via AWS CLI:**
```bash
export AWS_REGION="me-south-1"

# Create parameter group
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name datastream-replication-params \
  --db-parameter-group-family aurora-postgresql15 \
  --description "Enable logical replication for Datastream" \
  --region $AWS_REGION

# Enable logical replication
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name datastream-replication-params \
  --parameters "ParameterName=rds.logical_replication,ParameterValue=1,ApplyMethod=pending-reboot" \
  --region $AWS_REGION

echo "✅ Parameter group created!"
```

#### **Step 1.3: Assign Parameter Group to Cluster**

**From AWS Console:**
1. Go to RDS Dashboard → Databases
2. Select your Aurora cluster
3. Click "Modify"
4. In "Additional configuration" section:
   - **DB cluster parameter group:** Select `datastream-replication-params`
   - **Backup retention period:** Set to `7 days` (minimum)
5. Click "Continue"
6. Select "Apply immediately"
7. Click "Modify cluster"

**Or via AWS CLI:**
```bash
export DB_CLUSTER_ID="clx-master-rdsstack-44v5r2ek5smn-dbcluster-div5xs2dhop8"
export AWS_REGION="me-south-1"

# Modify cluster to use new parameter group
aws rds modify-db-cluster \
  --db-cluster-identifier $DB_CLUSTER_ID \
  --db-cluster-parameter-group-name datastream-replication-params \
  --backup-retention-period 7 \
  --apply-immediately \
  --region $AWS_REGION

echo "✅ Parameter group assigned!"
echo "⚠️  Reboot required for changes to take effect"
```

#### **Step 1.4: Reboot Aurora Cluster**

**⚠️ WARNING: This causes downtime! Coordinate with your team!**

**From AWS Console:**
1. Go to RDS Dashboard → Databases
2. Select your cluster
3. Actions → Reboot
4. Confirm

**Or via AWS CLI:**
```bash
# ⚠️ This will cause 5-10 minutes downtime!
aws rds reboot-db-cluster \
  --db-cluster-identifier $DB_CLUSTER_ID \
  --region $AWS_REGION

echo "Rebooting cluster... This takes 5-10 minutes"

# Monitor status
watch -n 30 "aws rds describe-db-clusters \
  --db-cluster-identifier $DB_CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].Status' \
  --output text"
```

---

### **PHASE 2: Create Datastream User & Configure Replication**

#### **Step 2.1: Connect to Aurora**

**From your GCP VM (which can reach Aurora through VPN):**

```bash
# SSH to VM
gcloud compute ssh test-vpn-connectivity --zone=me-central2-a

# Connect to Aurora using writer endpoint IP
PGPASSWORD='YOUR_TROFIADMIN_PASSWORD' psql \
  -h 172.27.25.41 \
  -U trofiadmin \
  -d inventory \
  -p 5432
```

#### **Step 2.2: Create Datastream User**

**Inside psql, run these commands:**

```sql
-- Create the datastream user
CREATE USER datastream WITH ENCRYPTED PASSWORD 'SMIFKRAEYKNQUL';

-- Grant replication privilege (required for CDC)
GRANT rds_replication TO datastream;

-- Grant database access
GRANT CONNECT ON DATABASE inventory TO datastream;

-- Grant schema usage
GRANT USAGE ON SCHEMA public TO datastream;

-- Grant SELECT on all existing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO datastream;

-- Grant SELECT on future tables (important!)
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO datastream;

-- Verify user was created
\du datastream
```

**Expected output:**
```
                              List of roles
  Role name  |                   Attributes                   | Member of
-------------+-----------------------------------------------+------------
 datastream  |                                               | {rds_replication}
```

#### **Step 2.3: Create Publication**

**What is a publication?**
It tells PostgreSQL which tables to track for changes.

**Option A: Publish specific tables (recommended - less load)**
```sql
-- Replace with your actual table names
CREATE PUBLICATION datastream_publication
FOR TABLE public.customers, public.orders, public.products, public.inventory;
```

**Option B: Publish all tables in public schema**
```sql
-- For PostgreSQL 15+ (easier but more load)
CREATE PUBLICATION datastream_publication
FOR TABLES IN SCHEMA public;
```

**Option C: Publish ALL tables in database**
```sql
-- Use only if you need everything (highest load)
CREATE PUBLICATION datastream_publication
FOR ALL TABLES;
```

**Verify publication:**
```sql
\dRp+ datastream_publication
```

#### **Step 2.4: Create Replication Slot**

**What is a replication slot?**
It's like a bookmark that keeps track of which changes Datastream has already read.

```sql
-- Create the replication slot
SELECT pg_create_logical_replication_slot('datastream_slot', 'pgoutput');
```

**Expected output:**
```
 pg_create_logical_replication_slot
------------------------------------
 (datastream_slot,0/12345678)
```

**Verify replication slot:**
```sql
SELECT * FROM pg_replication_slots WHERE slot_name = 'datastream_slot';
```

**Exit psql:**
```sql
\q
```

**Exit VM:**
```bash
exit
```

---

### **PHASE 3: Configure Google Cloud**

#### **Step 3.1: Enable Required APIs**

**From GCP Cloud Shell:**

```bash
# Enable APIs
gcloud services enable datastream.googleapis.com
gcloud services enable servicenetworking.googleapis.com
gcloud services enable bigquery.googleapis.com
gcloud services enable compute.googleapis.com

echo "Waiting for APIs to fully enable..."
sleep 30

echo "✅ APIs enabled!"
```

#### **Step 3.2: Create BigQuery Dataset**

```bash
# Create dataset for replicated data
bq mk --location=me-central2 --dataset trofi-data:aurora_replication

# Verify
bq ls --project_id=trofi-data

echo "✅ BigQuery dataset created!"
```

#### **Step 3.3: Allocate IP Range for Datastream**

```bash
# Allocate IP address range for private service connection
gcloud compute addresses create datastream-ip-range \
  --global \
  --purpose=VPC_PEERING \
  --prefix-length=24 \
  --network=datastream-vpn-network

echo "✅ IP range allocated!"
```

#### **Step 3.4: Create Private Service Connection**

```bash
# Create VPC peering for Datastream
gcloud services vpc-peerings connect \
  --service=servicenetworking.googleapis.com \
  --ranges=datastream-ip-range \
  --network=datastream-vpn-network

echo "Creating service connection... This takes 5-10 minutes"

# Monitor (wait until complete)
watch -n 30 "gcloud services vpc-peerings list \
  --network=datastream-vpn-network"

echo "✅ Private service connection created!"
```

#### **Step 3.5: Fix DNS (Important!)**

Datastream needs to resolve Aurora's hostname. Let's create static DNS records:

```bash
# Delete old forwarding zone if it exists
gcloud dns managed-zones delete aws-rds-forward --quiet 2>/dev/null || true

# Create private zone with static records
gcloud dns managed-zones create aws-rds-static \
  --description="Static DNS for AWS Aurora" \
  --dns-name="cxiai226s8b7.me-south-1.rds.amazonaws.com." \
  --networks=datastream-vpn-network \
  --visibility=private

# Add cluster endpoint (writer)
gcloud dns record-sets create \
  clx-master-rdsstack-44v5r2ek5smn-dbcluster-div5xs2dhop8.cluster.cxiai226s8b7.me-south-1.rds.amazonaws.com. \
  --zone=aws-rds-static \
  --type=A \
  --ttl=60 \
  --rrdatas=172.27.25.41

# Add writer instance
gcloud dns record-sets create \
  clx-master-rdsstack-44v5r2ek5smn-dbinstancewriter-sdi5bn4c7vw2.cxiai226s8b7.me-south-1.rds.amazonaws.com. \
  --zone=aws-rds-static \
  --type=A \
  --ttl=60 \
  --rrdatas=172.27.25.41

echo "✅ DNS records created!"

# Verify
gcloud dns record-sets list --zone=aws-rds-static
```

---

### **PHASE 4: Create Datastream Resources**

#### **Step 4.1: Create Connection Profile - Source (Aurora)**

**Option A: Using hostname (if DNS works)**
```bash
gcloud datastream connection-profiles create aurora-postgres-source \
  --location=me-central2 \
  --type=postgresql \
  --display-name="Aurora PostgreSQL Source" \
  --postgresql-hostname=clx-master-rdsstack-44v5r2ek5smn-dbcluster-div5xs2dhop8.cluster.cxiai226s8b7.me-south-1.rds.amazonaws.com \
  --postgresql-port=5432 \
  --postgresql-username=datastream \
  --postgresql-password='SMIFKRAEYKNQUL' \
  --postgresql-database=inventory \
  --static-ip-connectivity
```

**Option B: Using IP address (if DNS doesn't work)**
```bash
gcloud datastream connection-profiles create aurora-postgres-source \
  --location=me-central2 \
  --type=postgresql \
  --display-name="Aurora PostgreSQL Source" \
  --postgresql-hostname=172.27.25.41 \
  --postgresql-port=5432 \
  --postgresql-username=datastream \
  --postgresql-password='SMIFKRAEYKNQUL' \
  --postgresql-database=inventory \
  --static-ip-connectivity
```

**Test the connection:**
```bash
# Discover schema to verify connectivity
gcloud datastream connection-profiles discover aurora-postgres-source \
  --location=me-central2 \
  --postgresql-rdbms-file=/tmp/aurora-schema.json \
  --recursive

# Check the output file
cat /tmp/aurora-schema.json | jq '.'

echo "✅ Source connection profile created and tested!"
```

#### **Step 4.2: Create Connection Profile - Destination (BigQuery)**

```bash
gcloud datastream connection-profiles create bigquery-destination \
  --location=me-central2 \
  --type=bigquery \
  --display-name="BigQuery Destination"

echo "✅ Destination connection profile created!"
```

#### **Step 4.3: Create Datastream Stream**

```bash
# Create the replication stream
gcloud datastream streams create aurora-to-bigquery \
  --location=me-central2 \
  --display-name="Aurora to BigQuery Replication" \
  --source=aurora-postgres-source \
  --destination=bigquery-destination \
  --postgresql-source-config='{
    "publication": "datastream_publication",
    "replicationSlot": "datastream_slot",
    "includeObjects": {
      "postgresqlSchemas": [
        {
          "schema": "public"
        }
      ]
    }
  }' \
  --destination-config='{
    "sourceHierarchyDatasets": {
      "datasetTemplate": {
        "location": "me-central2",
        "datasetIdPrefix": "aurora_replication_"
      }
    }
  }' \
  --backfill-all

echo "Stream created! It will start in RUNNING state automatically"
```

**Or create with specific tables only:**
```bash
gcloud datastream streams create aurora-to-bigquery \
  --location=me-central2 \
  --display-name="Aurora to BigQuery Replication" \
  --source=aurora-postgres-source \
  --destination=bigquery-destination \
  --postgresql-source-config='{
    "publication": "datastream_publication",
    "replicationSlot": "datastream_slot",
    "includeObjects": {
      "postgresqlSchemas": [
        {
          "schema": "public",
          "postgresqlTables": [
            {"table": "customers"},
            {"table": "orders"},
            {"table": "products"},
            {"table": "inventory"}
          ]
        }
      ]
    }
  }' \
  --destination-config='{
    "sourceHierarchyDatasets": {
      "datasetTemplate": {
        "location": "me-central2",
        "datasetIdPrefix": "aurora_replication_"
      }
    }
  }' \
  --backfill-all
```

#### **Step 4.4: Monitor Stream Status**

```bash
# Check stream status
gcloud datastream streams describe aurora-to-bigquery \
  --location=me-central2

# Monitor in real-time
watch -n 30 "gcloud datastream streams describe aurora-to-bigquery \
  --location=me-central2 \
  --format='value(state)'"

# View logs
gcloud logging read "resource.type=datastream.googleapis.com/Stream" \
  --limit=50 \
  --format=json
```

---

### **PHASE 5: Verify Data Replication**

#### **Step 5.1: Check BigQuery**

**From GCP Cloud Shell:**

```bash
# List datasets
bq ls

# List tables in replication dataset
bq ls aurora_replication_inventory_public

# Count rows in a table
bq query --use_legacy_sql=false \
  'SELECT COUNT(*) as total_rows
   FROM `trofi-data.aurora_replication_inventory_public.customers`'

# View sample data
bq query --use_legacy_sql=false \
  'SELECT *
   FROM `trofi-data.aurora_replication_inventory_public.customers`
   LIMIT 10'
```

#### **Step 5.2: Test Real-Time Replication**

**In Aurora (via psql):**
```sql
-- Insert a test row
INSERT INTO customers (name, email, created_at)
VALUES ('Test Customer', 'test@example.com', NOW());
```

**Wait 10-30 seconds, then check BigQuery:**
```bash
bq query --use_legacy_sql=false \
  "SELECT *
   FROM \`trofi-data.aurora_replication_inventory_public.customers\`
   WHERE email = 'test@example.com'"
```

**If you see the row, replication is working! 🎉**

---

## **Troubleshooting**

### **Issue: Connection profile test fails**

**Check:**
1. VPN tunnel is UP: `gcloud compute vpn-tunnels describe ...`
2. Firewall allows port 5432 from Datastream IP ranges
3. Aurora security group allows inbound from VPN IP
4. Datastream user has correct password and permissions

### **Issue: Stream stuck in STARTING**

**Check:**
1. Publication exists: `\dRp+` in psql
2. Replication slot exists: `SELECT * FROM pg_replication_slots;`
3. Logical replication enabled: Check parameter group
4. Aurora was rebooted after enabling logical replication

### **Issue: No data appearing in BigQuery**

**Check:**
1. Stream state is RUNNING
2. Backfill is complete (check stream description)
3. Source tables have data
4. Tables are included in publication

### **Issue: "Replication slot already in use"**

**Fix:**
```sql
-- In psql, drop and recreate the slot
SELECT pg_drop_replication_slot('datastream_slot');
SELECT pg_create_logical_replication_slot('datastream_slot', 'pgoutput');
```

---

## **Monitoring & Maintenance**

### **Daily Checks**

```bash
# Stream health
gcloud datastream streams describe aurora-to-bigquery \
  --location=me-central2 \
  --format='value(state)'

# VPN health
gcloud compute vpn-tunnels describe vpn-tunnel-1 \
  --region=me-central2 \
  --format='value(status)'
```

### **Weekly Checks**

```bash
# Check replication lag
gcloud monitoring time-series list \
  --filter='metric.type="datastream.googleapis.com/stream/unsupported_event_count"'

# Check BigQuery storage
bq ls --project_id=trofi-data --format=json
```

---

## **Important Notes**

### **Publication Name:** `datastream_publication`
- You'll use this when creating the stream

### **Replication Slot Name:** `datastream_slot`
- You'll use this when creating the stream

### **Credentials:**
- Username: `datastream`
- Password: `SMIFKRAEYKNQUL`
- Database: `inventory`

### **Remember:**
- ✅ Aurora must be rebooted after enabling logical replication
- ✅ Backup retention must be at least 7 days
- ✅ VPN tunnel must be UP
- ✅ Publication and replication slot must exist before creating stream

---

## **Cost Estimate**

**Per Month (approximate):**
- Datastream: ~$360 (assuming 500 GB/month at $0.72/GB for first 5 TB)
- BigQuery storage: ~$20 (assuming 1 TB at $0.02/GB)
- VPN: ~$36 (one tunnel at $0.05/hour)
- **Total: ~$416/month**

---

## **Need Help?**

1. Check Datastream status: https://console.cloud.google.com/datastream/streams
2. View logs: https://console.cloud.google.com/logs
3. Official docs: https://cloud.google.com/datastream/docs
4. Support: Open ticket in GCP Console

---

**You're ready to go! 🚀 Follow the phases in order, and your data will flow from Aurora to BigQuery in real-time!**
