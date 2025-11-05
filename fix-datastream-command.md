# Fix for Datastream Private Connection Error

## The Problem
The `--vpc-peering-config` flag format is incorrect for your gcloud version.

## Solution - Try These Commands

### **Option 1: Updated Syntax (Try This First)**

```bash
gcloud datastream private-connections create datastream-to-aurora \
  --location=me-central2 \
  --display-name="Private connection to Aurora PostgreSQL" \
  --vpc=datastream-vpn-network \
  --subnet=10.200.1.0/29
```

### **Option 2: If Option 1 Fails - Use Full Resource Names**

First, get your project ID:
```bash
export PROJECT_ID=$(gcloud config get-value project)
echo "Project ID: $PROJECT_ID"
```

Then create the private connection:
```bash
gcloud datastream private-connections create datastream-to-aurora \
  --location=me-central2 \
  --display-name="Private connection to Aurora PostgreSQL" \
  --vpc=projects/$PROJECT_ID/global/networks/datastream-vpn-network \
  --subnet=10.200.1.0/29
```

### **Option 3: If Above Fails - Allocate IP Range First**

```bash
# Step 1: Allocate IP range for service networking
gcloud compute addresses create datastream-ip-range \
  --global \
  --purpose=VPC_PEERING \
  --prefix-length=29 \
  --network=datastream-vpn-network

# Step 2: Create service connection
gcloud services vpc-peerings connect \
  --service=servicenetworking.googleapis.com \
  --ranges=datastream-ip-range \
  --network=datastream-vpn-network

# Step 3: Now create private connection (without subnet)
gcloud datastream private-connections create datastream-to-aurora \
  --location=me-central2 \
  --display-name="Private connection to Aurora PostgreSQL" \
  --vpc=datastream-vpn-network
```

### **Option 4: Use Console Instead**

If all commands fail, create it via Console:

1. Go to: https://console.cloud.google.com/datastream/private-connections
2. Click "Create Private Connection"
3. Name: `datastream-to-aurora`
4. Region: `me-central2`
5. VPC: `datastream-vpn-network`
6. IP range: `10.200.1.0/29`
7. Click Create

---

## **What To Do Next**

1. **Try Option 1 first** (simplest)
2. If it gives an error, **try Option 2**
3. If still failing, **try Option 3** (more steps but robust)
4. Last resort: **Use Console** (Option 4)

After any option succeeds, verify with:
```bash
gcloud datastream private-connections describe datastream-to-aurora \
  --location=me-central2
```

---

## **Understanding The Error**

The error means gcloud doesn't recognize this format:
```
--vpc-peering-config=vpc=datastream-vpn-network,subnet=10.200.1.0/29
```

Google changed the command syntax in newer versions. The options above use the current syntax.
