import functions_framework
from google.cloud import bigquery
import os
import json
import threading
import sys
from flask import Flask, make_response
from flask_cors import CORS

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

def get_recursive_size(obj, seen=None):
    """Recursively finds the real size of an object in memory."""
    size = sys.getsizeof(obj)
    if seen is None:
        seen = set()
    obj_id = id(obj)
    if obj_id in seen:
        return 0
    seen.add(obj_id)
    if isinstance(obj, dict):
        size += sum([get_recursive_size(v, seen) for v in obj.values()])
        size += sum([get_recursive_size(k, seen) for k in obj.keys()])
    elif hasattr(obj, '__iter__') and not isinstance(obj, (str, bytes, bytearray)):
        size += sum([get_recursive_size(i, seen) for i in obj])
    return size

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
                    # We only store the set to save memory. We convert back to list during JSON serialization if needed.
                    all_alleles_list = row["All_Epitope_Alleles"] if row["All_Epitope_Alleles"] else []
                    required_alleles_list = row["Required_Alleles"] if row["Required_Alleles"] else []
                    
                    EPITOPE_DATA.append({
                        "Epitope ID": row["Epitope ID"],
                        "Epitope Name": row["Epitope Name"],
                        "Locus": row["Locus"],
                        # Optimized: Store ONLY the set for O(1) lookups and memory efficiency
                        "All_Epitope_Alleles_Set": set(all_alleles_list),
                        # Optimized: Store ONLY the set
                        "Required_Alleles_Set": {ra for ra in required_alleles_list if ra and ra.strip()}
                    })
                
                print(f"Successfully loaded {len(EPITOPE_DATA)} epitope rows.")
                # Detailed memory logging
                total_size = get_recursive_size(EPITOPE_DATA)
                print(f"[EPITOPE_DATA] Total recursive size: {total_size / 1024 / 1024:.2f} MiB for {len(EPITOPE_DATA)} rows")
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
        all_alleles_set = row.get("All_Epitope_Alleles_Set", set())
        
        positive_matches_set = all_alleles_set.intersection(input_alleles)
        
        # Filter out rows with no positive matches (as in the original SQL)
        if not positive_matches_set:
            continue
            
        positive_matches = list(positive_matches_set)

        # 2. Calculate Missing Required Alleles
        # Use pre-calculated set
        required_alleles_set = row.get("Required_Alleles_Set", set())
        missing_required_set = required_alleles_set.difference(input_alleles)
        missing_required = list(missing_required_set)

        # 3. Calculate Self Match Count using set intersection
        self_match_count = len(positive_matches_set.intersection(recipient_hla_set))

        # Build the result object
        results.append({
            "Epitope ID": row["Epitope ID"],
            "Epitope Name": row["Epitope Name"],
            "Locus": row["Locus"],
            # Convert set back to list for JSON serialization
            "All_Epitope_Alleles": list(all_alleles_set),
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

# Initialize Flask app for CORS handling
app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

@functions_framework.http
def fetch_bq_epitopes(request):
    """
    HTTP Cloud Function that retrieves epitope data from BigQuery (lazily cached),
    computes matches against input alleles, and returns the sorted results.
    """
    # Use Flask's request context to leverage flask-cors
    with app.test_request_context(
        path=request.path,
        method=request.method,
        headers=request.headers,
        data=request.get_data()
    ):
        try:
            # Ensure cache is populated if empty
            if EPITOPE_DATA is None or ALLELE_CACHE is None:
                load_epitope_data()
                
            # Normalize path by removing trailing slashes for consistent matching
            path = request.path.rstrip('/')

            # Handle CORS preflight request (OPTIONS) handled by flask-cors wrapper later
            # but we need to return a valid response from this function.
            # Actually, since we are using app.test_request_context,
            # we should let Flask handle the routing if we wanted full integration,
            # but for Cloud Functions, we just need to wrap the response.

            response_data = None
            status_code = 200
            content_type = "application/json"

            # Handle /robots.txt
            if path.endswith('/robots.txt'):
                response_data = "User-agent: *\nDisallow: /"
                content_type = "text/plain"
            
            # Handle /alleles endpoint
            elif path.endswith('/alleles'):
                response_data = json.dumps(ALLELE_CACHE)
            
            # Handle /warmup path or GET request (health check)
            elif path.endswith('/warmup') or request.method == 'GET':
                response_data = json.dumps({"status": "ready"})
            
            # Main POST logic for epitope matching
            elif request.method == 'POST':
                request_json = request.get_json(silent=True)
                if request_json is None:
                    response_data = json.dumps({"error": "Bad Request: Request body must be valid JSON."})
                    status_code = 400
                else:
                    input_alleles = set(request_json.get("input_alleles", []))
                    recipient_hla = set(request_json.get("recipient_hla", []))

                    if not input_alleles:
                        response_data = json.dumps({"error": "Bad Request: `input_alleles` array is required."})
                        status_code = 400
                    else:
                        # process_epitope_matching is CPU bound
                        results = process_epitope_matching(EPITOPE_DATA, input_alleles, recipient_hla)
                        response_data = json.dumps(results)
            
            else:
                response_data = json.dumps({"error": "Method Not Allowed"})
                status_code = 405

            response = make_response(response_data, status_code)
            response.headers["Content-Type"] = content_type
            
            # Apply CORS headers via flask-cors (this is a bit manual in Cloud Functions
            # but using flask-cors logic ensures consistency)
            return app.process_response(response)

        except Exception as e:
            print(f"Error in fetch_bq_epitopes: {e}")
            error_response = make_response(json.dumps({"error": f"Internal Server Error: {str(e)}"}), 500)
            error_response.headers["Content-Type"] = "application/json"
            return app.process_response(error_response)
