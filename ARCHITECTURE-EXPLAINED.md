# Datastream Replication Architecture - Simple Explanation

## **The Big Picture**

You're building a **real-time data bridge** between AWS and Google Cloud.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         YOUR SETUP                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  AWS (Bahrain Region)              Google Cloud (Saudi Region)     │
│  ┌─────────────────┐               ┌─────────────────────┐         │
│  │  Aurora DB      │               │                     │         │
│  │  PostgreSQL     │               │   BigQuery          │         │
│  │                 │               │   (Analytics DB)    │         │
│  │  Tables:        │   =========>  │                     │         │
│  │  - customers    │   Datastream  │   Same tables       │         │
│  │  - orders       │   copies      │   - customers       │         │
│  │  - products     │   changes     │   - orders          │         │
│  │  - inventory    │               │   - products        │         │
│  │                 │               │   - inventory       │         │
│  └─────────────────┘               └─────────────────────┘         │
│         ↑                                   ↑                       │
│         │                                   │                       │
│         │                                   │                       │
│  ┌──────┴──────┐                   ┌────────┴─────────┐            │
│  │  VPN Tunnel │←─── encrypted ───→│  VPN Tunnel      │            │
│  │  (AWS VGW)  │                   │  (GCP Gateway)   │            │
│  └─────────────┘                   └──────────────────┘            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## **The Components Explained**

### **1. Aurora PostgreSQL (AWS)**
- **What:** Your production database
- **Where:** AWS Bahrain (me-south-1)
- **Does:** Stores live data from your application
- **Example:** When a customer places an order, it's saved here

### **2. VPN Tunnel**
- **What:** Secure encrypted connection between AWS and Google
- **Why:** Datastream needs to access Aurora securely
- **Like:** A private highway between two cities

### **3. Datastream (Google Cloud)**
- **What:** A service that copies data changes
- **How:** Uses PostgreSQL's built-in replication feature
- **Like:** A copy machine that runs automatically 24/7

### **4. BigQuery (Google Cloud)**
- **What:** Analytics database
- **Where:** Google Cloud Saudi Arabia (me-central2)
- **Does:** Stores a copy of your data for analysis
- **Example:** Run reports on millions of orders in seconds

---

## **How Data Flows - Step by Step**

### **Example: A New Order Arrives**

```
Step 1: Customer places order
   ↓
Order saved to Aurora (AWS)
   ↓
Aurora writes to "WAL" (Write-Ahead Log)
   ↓
Datastream reads the WAL through VPN tunnel
   ↓
Datastream detects: "New order #12345"
   ↓
Datastream sends data through internet to BigQuery
   ↓
Order appears in BigQuery (2-5 seconds later)
```

---

## **Why We Need Each Step**

### **Step 1: Create Datastream User**
- **Why:** Datastream needs login credentials to read from Aurora
- **Like:** Giving someone a key to your house

### **Step 2: Enable Logical Replication**
- **Why:** Aurora needs to track changes for Datastream to read
- **Like:** Turning on security cameras to record what happens

### **Step 3: VPN Tunnel**
- **Why:** AWS and Google aren't directly connected
- **Like:** Building a bridge between two islands

### **Step 4: DNS Setup**
- **Why:** Datastream needs to find Aurora's address
- **Like:** Adding an address to GPS

### **Step 5: Private Connection**
- **Why:** Datastream needs a secure path through the VPN
- **Like:** Getting a VIP pass to use the private highway

### **Step 6: Connection Profiles**
- **Why:** Tell Datastream where to read from (Aurora) and write to (BigQuery)
- **Like:** Programming source and destination in GPS

### **Step 7: Create Stream**
- **Why:** Start the actual data copying
- **Like:** Pressing "Start" on the copy machine

---

## **What Happens After Setup**

### **Initial Sync (Backfill)**
1. Datastream reads ALL existing data from Aurora
2. Copies everything to BigQuery
3. Takes hours/days depending on data size

### **Ongoing Replication**
1. Every INSERT/UPDATE/DELETE in Aurora
2. Gets copied to BigQuery within seconds
3. Happens automatically forever

### **What You Can Do**
```sql
-- In Aurora (AWS)
INSERT INTO orders VALUES (12345, 'New Order', '2025-01-15');

-- Wait 2-5 seconds...

-- In BigQuery (Google Cloud) - same data appears!
SELECT * FROM orders WHERE order_id = 12345;
```

---

## **Real World Use Cases**

### **Before Replication:**
- ❌ Can't run big reports (slows down Aurora)
- ❌ Data stuck in AWS only
- ❌ Hard to combine with other Google data

### **After Replication:**
- ✅ Run massive queries in BigQuery (doesn't affect Aurora)
- ✅ Build dashboards with Google Data Studio
- ✅ Combine with Google Analytics, Sheets, etc.
- ✅ Train ML models on your data

---

## **Common Questions**

### **Q: Will this slow down my Aurora database?**
**A:** No! Datastream reads from the replication log, not from actual tables. It's like reading a diary, not bothering the person.

### **Q: What if Aurora goes down?**
**A:** Datastream pauses and resumes when Aurora comes back. No data is lost.

### **Q: What if I delete data in Aurora?**
**A:** By default, deletes are replicated too. But you can configure Datastream to keep deleted records in BigQuery.

### **Q: How much does this cost?**
**A:**
- Datastream: ~$0.50 per GB transferred
- BigQuery storage: ~$0.02 per GB per month
- VPN: ~$0.05 per hour

### **Q: Can I stop it?**
**A:** Yes! Just pause or delete the stream. Aurora is unaffected.

---

## **Current Status - What's Done**

✅ VPN tunnel created and working
✅ Network connectivity verified
✅ Datastream user created in Aurora
⏳ Need to fix: Private connection command
⏳ Need to do: Enable logical replication (requires Aurora reboot)

---

## **Next Steps - In Order**

1. **Fix the private connection command** (use the fix guide)
2. **Grant permissions to datastream user**
3. **Enable logical replication** (coordinate with boss - causes brief downtime)
4. **Create connection profiles**
5. **Start the stream**
6. **Monitor initial backfill**

---

## **Monitoring After Setup**

```bash
# Check stream status
gcloud datastream streams describe aurora-to-bigquery-prod \
  --location=me-central2

# Check BigQuery for new data
bq query --use_legacy_sql=false \
  'SELECT COUNT(*) FROM `trofi-data.aurora_replication.*`'

# View stream logs
gcloud logging read "resource.type=datastream.googleapis.com/Stream" \
  --limit 50 \
  --format=json
```

---

## **Troubleshooting**

### **If replication stops:**
1. Check VPN tunnel status (must be UP)
2. Check Aurora is running
3. Check Datastream user has permissions
4. Check connection profiles are valid

### **If data looks wrong:**
1. Check schema mapping in stream config
2. Check for BigQuery quotas
3. Look at Datastream error logs

---

## **Need Help?**

- Datastream docs: https://cloud.google.com/datastream/docs
- Support: Open ticket in GCP Console
- Emergency: Pause stream, investigate, resume

---

**Bottom Line:** You're building a real-time copy of your AWS database in Google Cloud for analytics. It's safe, automatic, and doesn't affect your production app! 🚀
