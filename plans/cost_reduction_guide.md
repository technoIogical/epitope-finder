# Cost Reduction & Billing Analysis: Eliminating E2 Charges

This guide addresses the "E2 CPU and RAM utilization" charges appearing in `us-west1`. While you might suspect Cloud Build, these specific charges are almost certainly tied to **Cloud Run** configuration or **Serverless VPC Access Connectors**.

---

## 1. The Verdict: Why you are seeing "E2" charges

In Google Cloud Billing, "E2" typically refers to the **E2 machine family** used by Compute Engine, Cloud Run (under the hood), and VPC Connectors.

*   **Cloud Build:** The standard (default) pool is billed as "Cloud Build" time, not E2 instances. It includes a free tier of 120 build-minutes per day. It is **not** the source of persistent E2 utilization charges.
*   **Cloud Run:** If a service is configured with **"CPU is always allocated"**, you are billed 24/7 for the CPU and RAM of the underlying E2 instance, even if no one is using the app.
*   **VPC Connectors:** Serverless VPC Access connectors use a minimum of 2-3 small E2 instances to maintain a bridge between Cloud Run and your VPC. These cost ~$15-$20/month regardless of traffic.

---

## 2. Solution 1: Change Cloud Run CPU Allocation

If your Cloud Run service is set to "Always Allocated," it will generate constant E2 charges. For a low-traffic or development app, you should switch this to "Only during request processing."

### Steps to Fix:
1.  Go to the [Cloud Run Console](https://console.cloud.google.com/run).
2.  Click on your service name (e.g., `epitope-backend` or `epitope-frontend`).
3.  Click **EDIT & DEPLOY NEW REVISION** at the top.
4.  Scroll down to the **CPU allocation** section.
5.  Select **"CPU is only allocated during request processing"**.
    *   *Note: This ensures you only pay when someone is actually using the app.*
6.  (Optional but Recommended) Under **Autoscaling**, ensure **Minimum number of instances** is set to `0`.
7.  Click **DEPLOY**.

---

## 3. Solution 2: Remove Serverless VPC Connectors

If you are not explicitly connecting to a private database (like Cloud SQL via private IP) or a private Redis instance, you likely do not need a VPC Connector.

### Steps to Check and Remove:
1.  In the search bar, type **Serverless VPC Access** and select it.
2.  Look for any connectors listed in the `us-west1` region.
3.  If you find one, check if it is being used:
    *   Go back to **Cloud Run** > Your Service > **EDIT & DEPLOY NEW REVISION**.
    *   Click the **Connections** tab.
    *   Look under **VPC Connectivity**.
    *   If "None" is selected, the connector is sitting idle and wasting money.
4.  **To Delete:** Go back to the **Serverless VPC Access** page, select the connector, and click **DELETE**.

---

## 4. Solution 3: Check for Accidental Compute Engine VMs

If neither of the above applies, an E2 VM may have been created accidentally.

### Steps to Check:
1.  Go to the [Compute Engine VM Instances](https://console.cloud.google.com/compute/instances) page.
2.  Filter by region `us-west1`.
3.  If any instances are running, click the three dots and select **DELETE** (or **STOP** if you want to keep the data but stop the billing).

---

## Summary Checklist for $0 Billing
- [ ] **Cloud Run CPU:** Set to "Only during request processing".
- [ ] **Cloud Run Instances:** Min instances set to `0`.
- [ ] **VPC Connectors:** Deleted (unless strictly required for private networking).
- [ ] **Compute Engine:** No running instances in `us-west1`.
- [ ] **Artifact Registry:** Cleanup policies active (to avoid storage costs over time).
