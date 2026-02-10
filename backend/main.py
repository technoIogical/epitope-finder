import functions_framework
from google.cloud import bigquery
import os
import asyncio
import json

EPITOPE_DATA = None
ALLELE_CACHE = None
PROJECT_ID = "epitopefinder-458404"

async def load_epitope_data():
    global EPITOPE_DATA, ALLELE_CACHE
    if EPITOPE_DATA is not None and ALLELE_CACHE is not None:
        return EPITOPE_DATA

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
            
            loop = asyncio.get_running_loop()
            rows = await loop.run_in_executor(None, lambda: list(query_job.result()))
            
            EPITOPE_DATA = [dict(row) for row in rows]
            print(f"Successfully loaded {len(EPITOPE_DATA)} epitope rows.")
        except Exception as e:
            print(f"Error loading epitope data from BigQuery: {e}")
            raise e

    # Fetch Allele List
    if ALLELE_CACHE is None:
        print("Loading allele list from BigQuery...")
        try:
            query = "SELECT allele_name FROM `epitopefinder-458404`.epitopes.allele_list ORDER BY allele_name"
            query_job = client.query(query)
            
            loop = asyncio.get_running_loop()
            rows = await loop.run_in_executor(None, lambda: list(query_job.result()))
            
            ALLELE_CACHE = [row["allele_name"] for row in rows]
            print(f"Successfully loaded {len(ALLELE_CACHE)} allele names.")
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
        all_alleles_list = row.get("All_Epitope_Alleles", [])
        all_alleles_set = set(all_alleles_list)
        
        positive_matches_set = all_alleles_set.intersection(input_alleles)
        
        # Filter out rows with no positive matches (as in the original SQL)
        if not positive_matches_set:
            continue
            
        positive_matches = list(positive_matches_set)

        # 2. Calculate Missing Required Alleles
        required_alleles_list = row.get("Required_Alleles", [])
        # Use set difference for missing required alleles
        required_alleles_set = {ra for ra in required_alleles_list if ra and ra.strip()}
        missing_required_set = required_alleles_set.difference(input_alleles)
        missing_required = list(missing_required_set)

        # 3. Calculate Self Match Count using set intersection
        self_match_count = len(positive_matches_set.intersection(recipient_hla_set))

        # Build the result object
        results.append({
            "Epitope ID": row["Epitope ID"],
            "Epitope Name": row["Epitope Name"],
            "Locus": row["Locus"],
            "All_Epitope_Alleles": all_alleles_list,
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
async def fetch_bq_epitopes(request):
    # Handle CORS preflight request
    if request.method == "OPTIONS":
        headers = {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization",
            "Access-Control-Max-Age": "3600",
        }
        return ("", 204, headers)

    headers = {
        "Access-Control-Allow-Origin": "*",
        "Content-Type": "application/json"
    }

    try:
        # Ensure cache is populated if empty
        if EPITOPE_DATA is None or ALLELE_CACHE is None:
            await load_epitope_data()
    except Exception as e:
        print(f"Initialization error: {e}")
        return (json.dumps({"error": f"Internal Server Error: Could not initialize data. {str(e)}"}), 500, headers)

    # Handle /robots.txt
    if request.path.endswith('/robots.txt'):
        return ("User-agent: *\nDisallow: /", 200, {"Content-Type": "text/plain", **headers})

    # Handle /alleles endpoint
    if request.path.endswith('/alleles'):
        return (json.dumps(ALLELE_CACHE), 200, headers)

    # Handle /warmup path or GET request (health check)
    if request.path.endswith('/warmup') or request.method == 'GET':
        return (json.dumps({"status": "ready"}), 200, headers)

    # Main POST logic
    request_json = request.get_json(silent=True)
    if request_json is None:
        return (json.dumps({"error": "Bad Request: Request body must be valid JSON."}), 400, headers)

    input_alleles = set(request_json.get("input_alleles", []))
    recipient_hla = set(request_json.get("recipient_hla", []))

    if not input_alleles:
        return (json.dumps({"error": "Bad Request: `input_alleles` array is required."}), 400, headers)

    try:
        # process_epitope_matching is CPU bound
        results = process_epitope_matching(EPITOPE_DATA, input_alleles, recipient_hla)
        return (json.dumps(results), 200, headers)
    except Exception as e:
        print(f"Processing error: {e}")
        return (json.dumps({"error": f"Internal Server Error during processing: {str(e)}"}), 500, headers)
