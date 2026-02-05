# Google Cloud Console Deployment Configuration Guide

This guide provides step-by-step instructions for configuring the CI/CD pipeline for the Epitope Finder project using the Google Cloud Console UI. This setup complements the [`cloudbuild.yaml`](./cloudbuild.yaml) file.

---

## 1. Creating Repositories in Artifact Registry

You need to create two separate Docker repositories to store your backend and frontend images.

### Create Backend Repository
1. Open the [Google Cloud Console](https://console.cloud.google.com/).
2. In the search bar at the top, type **Artifact Registry** and select it.
3. Click **+ CREATE REPOSITORY**.
4. **Name**: `backend-repo` (This matches the `_REPO` variable for backend).
5. **Format**: `Docker`.
6. **Mode**: `Standard`.
7. **Location Type**: `Region`.
8. **Region**: `us-west1` (Matches the region in `cloudbuild.yaml`).
9. Click **CREATE**.

### Create Frontend Repository
1. Repeat the steps above.
2. **Name**: `frontend-repo` (This matches the `_REPO` variable for frontend).
3. Keep all other settings the same (`Docker`, `Region: us-west1`).
4. Click **CREATE**.

---

## 2. Setting Cleanup Policies

To manage costs and storage, set policies to automatically delete old images or keep only the most recent ones.

### Step 1: Access Cleanup Policies
1. In **Artifact Registry**, click on the name of a repository (e.g., `backend-repo`).
2. Select the **CLEANUP POLICIES** tab.
3. Click **SET CLEANUP POLICY** (or **EDIT** if policies already exist).

### Step 2: Set Cleanup Policies
Click **ADD RULE** and configure according to the following recommendations:

#### Recommended: Keep the last 5 images
This ensures you always have recent versions for rollback while preventing storage bloat.
- **Name**: `keep-last-5`
- **Policy type**: Select `Keep most recent versions`.
- **Keep count**: Set to `5`.
- **Tag state**: Select `Any tag state` (to ensure both latest and SHA-tagged versions are considered).

#### Alternative: Delete images older than 30 days
Use this if you prefer a time-based cleanup instead of a version count.
- **Name**: `delete-older-than-30-days`
- **Policy type**: Select `Conditional delete`.
- **Older than**: Set to `30d`.
- **Tag state**: Select `Any tag state`.

### Reference: Available UI Fields
When creating rules, you will see these fields in the Google Cloud Console:
- **Name**: Unique identifier for the rule.
- **Policy type**: `Conditional delete`, `Conditional keep`, or `Keep most recent versions`.
- **Tag state**: `Any tag state`, `Tagged`, or `Untagged`.
- **Tag prefixes**: (Optional) Filter by specific tags.
- **Version prefixes**: (Optional) Filter by specific version strings.
- **Package prefixes**: (Optional) Filter by specific package names.
- **Older than**: Duration (e.g., `30d`) to trigger deletion.
- **Newer than**: Duration to exempt recent images from deletion.

4. Click **SAVE** after adding your rules.
5. Repeat these steps for `frontend-repo`.

---

## 3. Setting Up Cloud Build Triggers

### Connecting the GitHub Repository
1. In the search bar, type **Cloud Build** and select it.
2. Go to the **Repositories** tab in the left sidebar (under "Product Concept").
3. Click **CONNECT REPOSITORY**.
4. Select **GitHub (Cloud Build GitHub App)** and click **CONTINUE**.
5. Authenticate with GitHub and select your repository (e.g., `epitope-finder`).
6. Click **CONNECT**.

### Creating the Backend Trigger
1. Go to the **Triggers** tab in Cloud Build.
2. Click **CREATE TRIGGER**.
3. **Name**: `build-backend`.
4. **Event**: `Push to a branch`.
5. **Source**: Select your connected repository and branch (usually `^main$`).
6. **Configuration**: `Cloud Build configuration file (yaml or json)`.
7. **Cloud Build configuration file location**: `cloudbuild.yaml`.
8. **Filters (Included files)**:
    - Click **ADD FILE PATH**.
    - Type: `backend/**`.
9. **Advanced (Substitution variables)**:
    - Click **ADD VARIABLE**.
    - `_SERVICE_NAME`: `epitope-backend`
    - `_DIR`: `backend`
    - `_REPO`: `backend-repo`
10. Click **CREATE**.

### Creating the Frontend Trigger
1. Click **CREATE TRIGGER** again.
2. **Name**: `build-frontend`.
3. **Event**: `Push to a branch`.
4. **Source**: Select the same repository and branch.
5. **Configuration**: `Cloud Build configuration file (yaml or json)`.
6. **Cloud Build configuration file location**: `cloudbuild.yaml`.
7. **Filters (Included files)**:
    - Click **ADD FILE PATH**.
    - Type: `epitope_frontend/**`.
8. **Advanced (Substitution variables)**:
    - Click **ADD VARIABLE**.
    - `_SERVICE_NAME`: `epitope-frontend`
    - `_DIR`: `epitope_frontend`
    - `_REPO`: `frontend-repo`
9. Click **CREATE**.

---

## Summary of Substitution Variables

| Variable | Backend Trigger Value | Frontend Trigger Value |
| :--- | :--- | :--- |
| `_SERVICE_NAME` | `epitope-backend` | `epitope-frontend` |
| `_DIR` | `backend` | `epitope_frontend` |
| `_REPO` | `backend-repo` | `frontend-repo` |
