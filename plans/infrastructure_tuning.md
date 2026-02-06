# Infrastructure Tuning Recommendations for Cloud Run

Based on the in-memory backend architecture where the entire dataset is cached in RAM for sub-millisecond lookups, the following settings are recommended for the **Epitope Finder Backend**.

## 1. Memory Estimation & Scaling
The memory requirement is primarily driven by the dataset size when converted from JSON (or BigQuery rows) into Python dictionaries and lists.

*   **Current Dataset (~7MB JSON):** Minimal impact. The application will comfortably fit in **512MB**.
*   **Target Growth (300MB+ JSON):** Python's object overhead (dictionaries, lists, and strings) typically multiplies the raw data size by 3x to 5x. 
    *   300MB raw data $\approx$ 1GB - 1.5GB RAM usage.
*   **Recommendation:** 
    *   **Short-term:** 1GB (To allow for growth and concurrency overhead).
    *   **Long-term:** 2GB+ if the dataset exceeds 300MB.

## 2. Recommended Cloud Run Settings

| Setting | Recommendation | Rationale |
| :--- | :--- | :--- |
| **Memory Limit** | **1GB** | Provides a buffer for Python object overhead as the dataset grows beyond its current small size. |
| **CPU Allocation** | **1 CPU** | Matching logic is CPU-intensive. 1 CPU ensures fast processing of the in-memory lists. |
| **Concurrency** | **80** | Since lookups are in-memory and non-blocking (read-only), a single instance can handle high throughput. |
| **Min Instances** | **0** | Scales to zero when not in use to minimize costs. Note: The first request after inactivity will experience a "cold start" delay while the dataset is fetched from BigQuery. |

## 3. Implementation Steps

### Option A: Using gcloud CLI (Recommended)
Run the following command in your terminal to apply all settings at once. Replace `[SERVICE_NAME]` and `[REGION]` with your actual values (e.g., `epitope-backend` and `us-west1`).

```bash
gcloud run services update [SERVICE_NAME] \
  --memory 1Gi \
  --cpu 1 \
  --concurrency 80 \
  --min-instances 0 \
  --region [REGION]
```

### Option B: Using Google Cloud Console (UI)
1.  Go to the [Cloud Run Console](https://console.cloud.google.com/run).
2.  Click on your service name.
3.  Click **"EDIT & DEPLOY NEW REVISION"**.
4.  Under **Capacity**:
    *   Memory: Select **1 GiB**.
    *   CPU: Select **1**.
5.  Under **Autoscaling**:
    *   Minimum number of instances: Set to **0**.
  6.  Under **Container, Variables & Secrets, Connections, Security**:
    *   Go to the **Container** tab.
    *   Set **Maximum concurrency** to **80**.
7.  Click **DEPLOY**.

## 4. Cost Considerations
*   **Min Instances (0):** This is the most cost-effective setting. You only pay for CPU/Memory while the container is actively processing requests.
*   **Cold Start Impact:** Because the application loads the dataset from BigQuery on startup, the first user after a period of inactivity will wait ~2-5 seconds for the data to cache. Subsequent users within the "warm" window will experience sub-millisecond lookups.
*   **Efficiency:** By using in-memory lookups, you still avoid BigQuery scan costs for the vast majority of requests, even with cold starts.
