# Epitope Finder Optimization Plan

This document outlines a step-by-step plan to optimize the **Epitope Finder** project, focusing on balancing backend efficiency, frontend performance, and infrastructure costs.

---

## 1. Architectural Strategy: The Hybrid Backend

### 1.1 Problem Analysis
- **Current:** Every search triggers a BigQuery query. 
- **Cost:** BQ scans have a 10MB minimum charge and are expensive for frequent small lookups.
- **Latency:** SQL execution adds 1-3 seconds overhead.

### 1.2 Proposed Approach: On-Demand In-Memory Caching
The backend will remain on **Cloud Run** and will still "scale to zero" (turn off when not in use) to save costs.
1. **Lazy Loading:** On the first request after a "cold start," the backend fetches the table from BigQuery.
2. **Persistent Memory:** As long as the container is "warm," the data stays in its RAM.
3. **Fast Matching:** Subsequent requests use Python's built-in filtering (list comprehensions or Pandas) instead of calling BigQuery.

### 1.3 Scalability & Cost Analysis (The "CPU vs. BigQuery" Trade-off)
- **CPU Time:** Processing 7MB (or even 300MB) of data in Python memory takes **milliseconds**. Cloud Run is billed in 100ms increments. A memory-based search will almost always finish within a single billing increment.
- **BigQuery Cost:** BigQuery scans are billed at a minimum of 10MB per query. At $5/TB, this sounds small, but if you have 1,000 searches, you are paying for 10GB of scans.
- **Comparison:**
    - **Memory Approach:** You pay for the CPU time of the container being "awake." Since the search is near-instant, the container can handle many requests within a few seconds of billable time.
    - **SQL Approach:** You pay for the CPU time (which includes waiting for BigQuery to respond, usually 1-3s) **PLUS** the BigQuery scan cost.
- **Conclusion:** The memory approach is **significantly cheaper** because it eliminates the BQ scan fee and reduces the "billable awake time" of the Cloud Run instance by removing the wait for SQL execution.
- **Data Growth (300MB+):** Even at 300MB, searching through a list in Python is faster than a remote network call to a database. The cost efficiency remains until the data is so large that it requires specialized indexing (multi-GB).

---

## 2. Frontend Performance (Optimization of `lib/main.dart`)

### 2.1 Rendering Optimization (Matrix View)
**Observation:** The matrix is heavy to render.
**Optimization:**
- **RepaintBoundary:** Wrap the static headers and the dynamic matrix in `RepaintBoundary`. This prevents the headers from repainting when the matrix scrolls and vice-versa.
- **Viewport-aware Painting:** Update `HeatmapRowPainter` to only draw the columns that are currently visible on the screen.
- **Pre-calculating Row Layouts:** Calculate `hasS`, `hasD`, and row colors *once* when the data arrives, instead of calculating them inside the `build` method for every frame.

### 2.2 UX Enhancements
- **Optimistic State:** Don't clear the previous results until the new ones have successfully arrived, reducing "white screen" flickering.

---

## 3. Infrastructure & Cost Optimization

### 3.1 Cloud Run Tuning
- **Concurrency:** Set to 80+. Since the backend will be processing searches in memory, one container can handle many users.
- **Memory:** Allocate 512MB (current) or 1GB (for 300MB+ data).
- **Scaling:** Keep `min-instances: 0` to ensure costs are $0 when no one is using the app.

---

## 4. Step-by-Step Implementation Plan

### Phase 1: Backend Memory Shift
1. [ ] **Global State:** Implement a global `EPITOPE_DATA` variable in `main.py`.
2. [ ] **On-Demand Loader:** Write a function that checks if `EPITOPE_DATA` is null and fetches it from BigQuery if so.
3. [ ] **Python Matching Logic:** Translate the current SQL logic (`Matches` CTE) into Python code to filter the `EPITOPE_DATA`.

### Phase 2: Frontend "Smooth Out"
1. [ ] **Repaint Boundaries:** Add to `main.dart` to isolate scroll/paint areas.
2. [ ] **Painter Optimization:** Update `HeatmapRowPainter` with viewport logic (calculating `startX` and `endX` based on scroll position).
3. [ ] **Data Model:** Create an `EpitopeRow` class that stores pre-calculated flags like `isHighlighted`.

### Phase 3: Deployment & Validation
1. [ ] **Cloud Run Tuning:** Update deployment configuration with higher concurrency.
2. [ ] **Verification:** Ensure the Python matching logic handles "Missing Required Alleles" and "Self Match Count" exactly as the SQL did.
