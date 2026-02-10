import functions_framework
from google.cloud import bigquery
import os
import json
import threading
import sys

# Try to import resource for memory tracking (Linux/Unix only)
try:
    import resource
except ImportError:
    resource = None

EPITOPE_DATA = None
ALLELE_CACHE = None
PROJECT_ID = "epitopefinder-458404"
# Lock to prevent race conditions during initialization
INIT_LOCK = threading.Lock()

def log_memory_usage(tag):
    if resource:
        usage = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        # On Linux, ru_maxrss is in kilobytes
        print(f"[{tag}] Memory Usage: {usage / 1024:.2f} MiB")
    else:
        # Fallback or Windows
        print(f"[{tag}] Memory tracking not available (resource module missing).")

def load_epitope_data():
    global EPITOPE_DATA, ALLELE_CACHE
    
    # Fast check without lock
    if EPITOPE_DATA is not None and ALLELE_CACHE is not None:
        return EPITOPE_DATA

    with INIT_LOCK:
        # Double-check inside lock
        if EPITOPE_DATA is not None and ALLELE_CACHE is not None:
            return EPITOPE_DATA
            
        log_memory_usage("Start Loading")

        client = bigquery.Client(project=PROJECT_ID)

        # Fetch Epitope Data
        if EPITOPE_DATA is None:
            print("Loading epitope data from BigQuery...")
            try:
                query = """
                    SELECT
                        epitope_id AS `Epitope ID`,
                        epitope_name AS `Epitope Name`,
                        locus AS Locus,
                        alleles AS All_Epitope_Alleles,
                        required_alleles AS Required_Alleles
                    FROM
                        `epitopefinder-458404`.epitopes.HLA_data
                """
                query_job = client.query(query)
                
                # Streaming execution to save memory
                EPITOPE_DATA = []
                for row in query_job.result():
                    # Pre-convert lists to sets for faster lookup and reduced memory churn during requests
                    all_alleles_list = row["All_Epitope_Alleles"] if row["All_Epitope_Alleles"] else []
                    required_alleles_list = row["Required_Alleles"] if row["Required_Alleles"] else []
                    
                    EPITOPE_DATA.append({
                        "Epitope ID": row["Epitope ID"],
                        "Epitope Name": row["Epitope Name"],
                        "Locus": row["Locus"],
                        # Store original list for JSON serialization
                        "All_Epitope_Alleles": all_alleles_list,
                        # Pre-calculate set for O(1) lookups
                        "_All_Epitope_Alleles_Set": set(all_alleles_list),
                        # Store original list
                        "Required_Alleles": required_alleles_list,
                        # Pre-calculate set
                        "_Required_Alleles_Set": {ra for ra in required_alleles_list if ra and ra.strip()}
                    })
                
                print(f"Successfully loaded {len(EPITOPE_DATA)} epitope rows.")
                log_memory_usage("After Epitope Load")
            except Exception as e:
                print(f"Error loading epitope data from BigQuery: {e}")
                raise e

        # Fetch Allele List
        if ALLELE_CACHE is None:
            print("Loading allele list from BigQuery...")
            try:
                query = "SELECT allele_name FROM `epitopefinder-458404`.epitopes.allele_list ORDER BY allele_name"
                query_job = client.query(query)
                
                # Streaming execution to save memory
                ALLELE_CACHE = [row["allele_name"] for row in query_job.result()]
                
                print(f"Successfully loaded {len(ALLELE_CACHE)} allele names.")
                log_memory_usage("After Allele Load")
            except Exception as e:
                print(f"Error loading allele list from BigQuery: {e}")
                raise e

    return EPITOPE_DATA

def process_epitope_matching(data, input_alleles, recipient_hla):
    results = []
    
    # Pre-calculate recipient HLA for faster intersection
    recipient_hla_set = set(recipient_hla)
    
    for row in data:
        # 1. Calculate Positive Matches using set intersection for speed
        # Use pre-calculated set
        all_alleles_set = row.get("_All_Epitope_Alleles_Set", set())
        
        positive_matches_set = all_alleles_set.intersection(input_alleles)
        
        # Filter out rows with no positive matches (as in the original SQL)
        if not positive_matches_set:
            continue
            
        positive_matches = list(positive_matches_set)

        # 2. Calculate Missing Required Alleles
        # Use pre-calculated set
        required_alleles_set = row.get("_Required_Alleles_Set", set())
        missing_required_set = required_alleles_set.difference(input_alleles)
        missing_required = list(missing_required_set)

        # 3. Calculate Self Match Count using set intersection
        self_match_count = len(positive_matches_set.intersection(recipient_hla_set))

        # Build the result object
        results.append({
            "Epitope ID": row["Epitope ID"],
            "Epitope Name": row["Epitope Name"],
            "Locus": row["Locus"],
            # Use the reference to the original list to save memory/avoid copy
            "All_Epitope_Alleles": row["All_Epitope_Alleles"],
            "Positive Matches": positive_matches,
            "Missing Required Alleles": missing_required,
            "Number of Positive Matches": len(positive_matches),
            "Number of Missing Required Alleles": len(missing_required),
            "Self_Match_Count": self_match_count
        })

    # 4. Sorting logic (O(N log N))
    results.sort(key=lambda x: (
        x["Self_Match_Count"],
        -x["Number of Positive Matches"],
        x["Number of Missing Required Alleles"]
    ))

    return results

@functions_framework.http
def fetch_bq_epitopes(request):
    """
    HTTP Cloud Function that retrieves epitope data from BigQuery (lazily cached),
    computes matches against input alleles, and returns the sorted results.
    """
    # Define CORS headers to be used in ALL responses
    cors_headers = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
        "Access-Control-Max-Age": "3600",
    }

    # Handle CORS preflight request (OPTIONS) immediately
    if request.method == "OPTIONS":
        return ("", 204, cors_headers)

    # Default headers for successful JSON responses
    json_headers = {**cors_headers, "Content-Type": "application/json"}

    try:
        # Ensure cache is populated if empty
        if EPITOPE_DATA is None or ALLELE_CACHE is None:
            load_epitope_data()
            
        # Normalize path by removing trailing slashes for consistent matching
        path = request.path.rstrip('/')

        # Handle /robots.txt
        if path.endswith('/robots.txt'):
            return ("User-agent: *\nDisallow: /", 200, {**cors_headers, "Content-Type": "text/plain"})

        # Handle /alleles endpoint
        if path.endswith('/alleles'):
            return (json.dumps(ALLELE_CACHE), 200, json_headers)

        # Handle /warmup path or GET request (health check)
        if path.endswith('/warmup') or request.method == 'GET':
            return (json.dumps({"status": "ready"}), 200, json_headers)

        # Main POST logic for epitope matching
        request_json = request.get_json(silent=True)
        if request_json is None:
            return (json.dumps({"error": "Bad Request: Request body must be valid JSON."}), 400, json_headers)

        input_alleles = set(request_json.get("input_alleles", []))
        recipient_hla = set(request_json.get("recipient_hla", []))

        if not input_alleles:
            return (json.dumps({"error": "Bad Request: `input_alleles` array is required."}), 400, json_headers)

        # process_epitope_matching is CPU bound
        results = process_epitope_matching(EPITOPE_DATA, input_alleles, recipient_hla)
        return (json.dumps(results), 200, json_headers)

    except Exception as e:
        print(f"Error in fetch_bq_epitopes: {e}")
        # Always return CORS headers even on internal errors
        return (json.dumps({"error": f"Internal Server Error: {str(e)}"}), 500, json_headers)
