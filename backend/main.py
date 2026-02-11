import functions_framework
from google.cloud import bigquery
import os
import psutil
import gc
import logging
import time

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def log_memory(stage: str):
    """Logs current memory usage."""
    process = psutil.Process(os.getpid())
    mem_info = process.memory_info()
    # rss: Resident Set Size (RAM used)
    # vms: Virtual Memory Size
    logger.info(f"Memory Log [{stage}]: RSS={mem_info.rss / 1024 / 1024:.2f} MB, VMS={mem_info.vms / 1024 / 1024:.2f} MB")

log_memory("Startup")

class EpitopeRecord:
    __slots__ = (
        'id', 'name', 'locus', 'alleles', 'required',
        'alleles_set', 'required_set'
    )
    def __init__(self, row):
        self.id = row["Epitope ID"]
        self.name = row["Epitope Name"]
        self.locus = row["Locus"]
        self.alleles = row["All_Epitope_Alleles"]
        self.required = row["Required_Alleles"]
        # Pre-calculate sets for faster intersection
        self.alleles_set = set(self.alleles) if self.alleles else set()
        self.required_set = {ra for ra in self.required if ra and ra.strip()} if self.required else set()

EPITOPE_DATA = None
ALLELE_CACHE = None
PROJECT_ID = "epitopefinder-458404"

def load_epitope_data():
    global EPITOPE_DATA, ALLELE_CACHE
    if EPITOPE_DATA is not None and ALLELE_CACHE is not None:
        return EPITOPE_DATA

    client = bigquery.Client(project=PROJECT_ID)

    # Fetch Epitope Data
    if EPITOPE_DATA is None:
        logger.info("Loading epitope data from BigQuery...")
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
            # Optimization: Use __slots__ to reduce memory footprint per object
            EPITOPE_DATA = [EpitopeRecord(dict(row)) for row in query_job.result()]
            logger.info(f"Successfully loaded {len(EPITOPE_DATA)} epitope records.")
            log_memory("After Epitope Data Load")
        except Exception as e:
            logger.error(f"Error loading epitope data from BigQuery: {e}")
            raise e

    # Fetch Allele List
    if ALLELE_CACHE is None:
        logger.info("Loading allele list from BigQuery...")
        try:
            query = "SELECT allele_name FROM epitopefinder-458404.epitopes.allele_list ORDER BY allele_name"
            query_job = client.query(query)
            # Use tuple for immutable, smaller cache
            ALLELE_CACHE = tuple(row["allele_name"] for row in query_job.result())
            logger.info(f"Successfully loaded {len(ALLELE_CACHE)} allele names.")
            log_memory("After Allele Cache Load")
        except Exception as e:
            logger.error(f"Error loading allele list from BigQuery: {e}")
            raise e

    return EPITOPE_DATA

def process_epitope_matching(data, input_alleles, recipient_hla):
    results = []
    
    for record in data:
        # 1. Calculate Positive Matches using pre-calculated set
        positive_matches_set = record.alleles_set.intersection(input_alleles)
        
        # Filter out rows with no positive matches
        if not positive_matches_set:
            continue
            
        positive_matches = list(positive_matches_set)

        # 2. Calculate Missing Required Alleles using pre-calculated set
        missing_required_set = record.required_set.difference(input_alleles)
        missing_required = list(missing_required_set)

        # 3. Calculate Self Match Count
        self_match_count = len(positive_matches_set.intersection(recipient_hla))

        # Build the result object
        results.append({
            "Epitope ID": record.id,
            "Epitope Name": record.name,
            "Locus": record.locus,
            "All_Epitope_Alleles": record.alleles,
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
    if request.method == "OPTIONS":
        headers = {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, GET",
            "Access-Control-Allow-Headers": "Content-Type, Authorization",
            "Access-Control-Max-Age": "3600",
        }
        return ("", 204, headers)

    headers = {"Access-Control-Allow-Origin": "*"}

    # Ensure cache is populated if empty
    if EPITOPE_DATA is None or ALLELE_CACHE is None:
        try:
            load_epitope_data()
            gc.collect()
            log_memory("Post-Initialization GC")
        except Exception as e:
            return (f"Internal Server Error: Could not initialize data. {str(e)}", 500, headers)

    # Handle /alleles endpoint
    if request.path.endswith('/alleles'):
        return (ALLELE_CACHE, 200, headers)

    # Handle /warmup path or GET request
    if request.path.endswith('/warmup') or request.method == 'GET':
        return ({"status": "ready"}, 200, headers)

    request_json = request.get_json(silent=True)
    if request_json is None:
        return ("Bad Request: Request body must be valid JSON.", 400, headers)

    input_alleles = set(request_json.get("input_alleles", []))
    recipient_hla = set(request_json.get("recipient_hla", []))

    if not input_alleles:
        return ("Bad Request: `input_alleles` array is required.", 400, headers)

    log_memory("Pre-Processing Request")
    results = process_epitope_matching(EPITOPE_DATA, input_alleles, recipient_hla)
    log_memory("Post-Processing Request")

    # Force GC after processing to keep memory footprint low
    gc.collect()
    
    return (results, 200, headers)
