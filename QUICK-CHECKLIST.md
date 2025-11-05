# Quick Start Checklist - What To Do Now

## **✅ Already Done**
- [x] VPN tunnel created and working
- [x] Network connectivity verified (can reach Aurora from GCP)
- [x] Basic Datastream user exists

---

## **🔴 Do These Steps NOW (No Downtime)**

### **1. Grant Proper Permissions to Datastream User** ⏱️ 5 minutes

```bash
# SSH to VM
gcloud compute ssh test-vpn-connectivity --zone=me-central2-a

# Connect to Aurora
PGPASSWORD='YOUR_TROFIADMIN_PASSWORD' psql \
  -h 172.27.25.41 \
  -U trofiadmin \
  -d inventory \
  -p 5432
```

**Run in psql:**
```sql
-- Grant replication role
GRANT rds_replication TO datastream;

-- Grant schema access
GRANT USAGE ON SCHEMA public TO datastream;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO datastream;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO datastream;

-- Create publication (choose one option)
-- OPTION A: Specific tables (recommended)
CREATE PUBLICATION datastream_publication
FOR TABLE public.customers, public.orders, public.products;

-- OPTION B: All tables in public schema
CREATE PUBLICATION datastream_publication
FOR TABLES IN SCHEMA public;

-- Create replication slot
SELECT pg_create_logical_replication_slot('datastream_slot', 'pgoutput');

-- Verify
\dRp+ datastream_publication
SELECT * FROM pg_replication_slots WHERE slot_name = 'datastream_slot';

-- Exit
\q
exit
```

---

### **2. Enable Google Cloud APIs** ⏱️ 2 minutes

```bash
gcloud services enable datastream.googleapis.com
gcloud services enable servicenetworking.googleapis.com
gcloud services enable bigquery.googleapis.com

sleep 30

echo "✅ APIs enabled!"
```

---

### **3. Create BigQuery Dataset** ⏱️ 1 minute

```bash
bq mk --location=me-central2 --dataset trofi-data:aurora_replication

bq ls

echo "✅ Dataset created!"
```

---

### **4. Fix DNS** ⏱️ 3 minutes

```bash
# Create private DNS zone
gcloud dns managed-zones create aws-rds-static \
  --description="Static DNS for AWS Aurora" \
  --dns-name="cxiai226s8b7.me-south-1.rds.amazonaws.com." \
  --networks=datastream-vpn-network \
  --visibility=private

# Add cluster endpoint
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

gcloud dns record-sets list --zone=aws-rds-static

echo "✅ DNS configured!"
```

---

## **🟡 Coordinate with Boss (Requires Downtime)**

### **5. Enable Logical Replication & Reboot Aurora** ⏱️ 15-20 minutes

**⚠️ THIS CAUSES 5-10 MINUTES DOWNTIME - Get approval first!**

**From AWS CloudShell:**

```bash
export AWS_REGION="me-south-1"
export DB_CLUSTER_ID="clx-master-rdsstack-44v5r2ek5smn-dbcluster-div5xs2dhop8"

# Get current parameter group
CURRENT_PARAM_GROUP=$(aws rds describe-db-clusters \
  --db-cluster-identifier $DB_CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].DBClusterParameterGroup' \
  --output text)

echo "Current Parameter Group: $CURRENT_PARAM_GROUP"

# Check if logical replication is already enabled
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name $CURRENT_PARAM_GROUP \
  --region $AWS_REGION \
  --query "Parameters[?ParameterName=='rds.logical_replication']" \
  --output table
```

**If it shows `0` (disabled), then enable it:**

```bash
# Enable logical replication
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name $CURRENT_PARAM_GROUP \
  --parameters "ParameterName=rds.logical_replication,ParameterValue=1,ApplyMethod=pending-reboot" \
  --region $AWS_REGION

# Set backup retention to 7 days (required)
aws rds modify-db-cluster \
  --db-cluster-identifier $DB_CLUSTER_ID \
  --backup-retention-period 7 \
  --apply-immediately \
  --region $AWS_REGION

echo "✅ Parameters modified!"
echo "⚠️  Now you need to reboot Aurora"
```

**⚠️ COORDINATE DOWNTIME WITH YOUR TEAM, then reboot:**

```bash
# THIS CAUSES DOWNTIME!
aws rds reboot-db-cluster \
  --db-cluster-identifier $DB_CLUSTER_ID \
  --region $AWS_REGION

echo "Rebooting... This takes 5-10 minutes"

# Monitor status
watch -n 30 "aws rds describe-db-clusters \
  --db-cluster-identifier $DB_CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].Status' \
  --output text"
```

**Wait until status shows `available` again**

---

## **🟢 Do These Steps AFTER Aurora Reboot**

### **6. Setup Datastream Networking** ⏱️ 10-15 minutes

**The command that failed before - here's the CORRECT way:**

```bash
# Step 6a: Allocate IP range
gcloud compute addresses create datastream-ip-range \
  --global \
  --purpose=VPC_PEERING \
  --prefix-length=24 \
  --network=datastream-vpn-network

# Step 6b: Create VPC peering
gcloud services vpc-peerings connect \
  --service=servicenetworking.googleapis.com \
  --ranges=datastream-ip-range \
  --network=datastream-vpn-network

echo "Creating VPC peering... Wait 5-10 minutes"

# Monitor until COMPLETE
watch -n 30 "gcloud services vpc-peerings list \
  --network=datastream-vpn-network \
  --format='value(state)'"

echo "✅ Datastream networking ready!"
```

---

### **7. Create Connection Profiles** ⏱️ 5 minutes

**Source (Aurora):**
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

# Test it
gcloud datastream connection-profiles discover aurora-postgres-source \
  --location=me-central2 \
  --postgresql-rdbms-file=/tmp/aurora-schema.json \
  --recursive

cat /tmp/aurora-schema.json

echo "✅ Source profile created!"
```

**Destination (BigQuery):**
```bash
gcloud datastream connection-profiles create bigquery-destination \
  --location=me-central2 \
  --type=bigquery \
  --display-name="BigQuery Destination"

echo "✅ Destination profile created!"
```

---

### **8. Create Datastream Stream** ⏱️ 3 minutes

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

echo "✅ Stream created and starting!"

# Monitor
gcloud datastream streams describe aurora-to-bigquery \
  --location=me-central2
```

---

### **9. Verify Replication Working** ⏱️ 2 minutes

**Check BigQuery:**
```bash
# Wait a few minutes for initial backfill, then check
bq ls aurora_replication_inventory_public

# Count rows
bq query --use_legacy_sql=false \
  'SELECT
     table_name,
     COUNT(*) as row_count
   FROM `trofi-data.aurora_replication_inventory_public.INFORMATION_SCHEMA.TABLES`
   GROUP BY table_name'

# View sample data
bq query --use_legacy_sql=false \
  'SELECT *
   FROM `trofi-data.aurora_replication_inventory_public.customers`
   LIMIT 5'
```

**Test real-time replication:**
```bash
# In Aurora, insert a test row (via psql)
INSERT INTO customers (name, email) VALUES ('Test User', 'test@test.com');

# Wait 30 seconds, then check BigQuery
bq query --use_legacy_sql=false \
  "SELECT * FROM \`trofi-data.aurora_replication_inventory_public.customers\`
   WHERE email = 'test@test.com'"

# If you see the row, IT WORKS! 🎉
```

---

## **Timeline Summary**

| Step | Time | Downtime? | When |
|------|------|-----------|------|
| 1. Grant permissions | 5 min | No | Now |
| 2. Enable APIs | 2 min | No | Now |
| 3. Create dataset | 1 min | No | Now |
| 4. Fix DNS | 3 min | No | Now |
| **5. Enable replication & reboot** | **15 min** | **YES** | **Coordinate with boss** |
| 6. Setup networking | 15 min | No | After reboot |
| 7. Create profiles | 5 min | No | After reboot |
| 8. Create stream | 3 min | No | After reboot |
| 9. Verify | 2 min | No | After stream starts |
| **TOTAL** | **~50 min** | **5-10 min** | |

---

## **Common Issues & Fixes**

### **Issue: gcloud command not recognized**
**Solution:** Make sure you're in GCP Cloud Shell, not AWS CloudShell

### **Issue: aws command not recognized**
**Solution:** Make sure you're in AWS CloudShell, not GCP Cloud Shell

### **Issue: "Publication already exists"**
**Solution:** Drop it first: `DROP PUBLICATION datastream_publication;`

### **Issue: Connection profile test fails**
**Solution:**
1. Check VPN is UP: `gcloud compute vpn-tunnels describe vpn-tunnel-1 --region=me-central2`
2. Try using IP instead of hostname: `--postgresql-hostname=172.27.25.41`

### **Issue: Stream stuck in STARTING**
**Solution:**
1. Check Aurora was rebooted after enabling logical replication
2. Check publication exists: `\dRp+` in psql
3. Check replication slot exists: `SELECT * FROM pg_replication_slots;`

---

## **What You'll See When It Works**

### **In GCP Console:**
- Stream status: **RUNNING** (green)
- Errors: **0**
- Backfill: **Complete**

### **In BigQuery:**
- Dataset: `aurora_replication_inventory_public`
- Tables: Same as in Aurora (customers, orders, etc.)
- Data: Continuously updated (30 second lag)

### **In Aurora:**
```sql
SELECT * FROM pg_replication_slots WHERE slot_name = 'datastream_slot';
-- Shows: active = true, with a restart_lsn value
```

---

## **Key Information to Remember**

- **Publication:** `datastream_publication`
- **Replication Slot:** `datastream_slot`
- **Username:** `datastream`
- **Password:** `SMIFKRAEYKNQUL`
- **Database:** `inventory`
- **Aurora Writer IP:** `172.27.25.41`
- **VPN Network:** `datastream-vpn-network`

---

## **Next Steps After Setup**

1. **Monitor**: Set up alerts for stream health
2. **Optimize**: Add indexes in BigQuery for your queries
3. **Schedule**: Create scheduled queries in BigQuery for reports
4. **Visualize**: Connect Google Data Studio to BigQuery
5. **Automate**: Set up Cloud Functions to process new data

---

**Ready to start? Begin with Step 1! 🚀**
