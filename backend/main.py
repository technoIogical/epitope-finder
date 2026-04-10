import functions_framework
from google.cloud import bigquery
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

ALLELE_CACHE = None
PROJECT_ID = "epitopefinder-458404"

def load_allele_cache():
    global ALLELE_CACHE
    if ALLELE_CACHE is not None:
        return ALLELE_CACHE

    client = bigquery.Client(project=PROJECT_ID)

    # Fetch Allele List and Serotype List for autocomplete
    logger.info("Loading autocomplete list from BigQuery...")
    try:
        query_alleles = "SELECT allele_name FROM `epitopefinder-458404`.epitopes.allele_list"
        query_serotypes = "SELECT DISTINCT serotype FROM `epitopefinder-458404`.epitopes.serotype_mapping"
        
        alleles = [row["allele_name"] for row in client.query(query_alleles).result()]
        serotypes = [row["serotype"] for row in client.query(query_serotypes).result()]
        
        # Combine, remove duplicates, and sort
        ALLELE_CACHE = tuple(sorted(list(set(alleles + serotypes))))
        logger.info(f"Successfully loaded {len(ALLELE_CACHE)} autocomplete items.")
    except Exception as e:
        logger.error(f"Error loading autocomplete list: {e}")
        raise e

    return ALLELE_CACHE

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

    # Handle /alleles endpoint
    if request.path.endswith('/alleles'):
        try:
            cache = load_allele_cache()
            return (list(cache), 200, headers)
        except Exception as e:
            return (f"Internal Server Error: Could not load alleles. {str(e)}", 500, headers)

    # Handle /warmup path or GET request
    if request.path.endswith('/warmup') or request.method == 'GET':
        return ({"status": "ready"}, 200, headers)

    request_json = request.get_json(silent=True)
    if request_json is None:
        return ("Bad Request: Request body must be valid JSON.", 400, headers)

    input_alleles = request_json.get("input_alleles", [])
    recipient_hla = request_json.get("recipient_hla", [])
    donor_hla = request_json.get("donor_hla", [])

    if not input_alleles:
        return ("Bad Request: `input_alleles` array is required.", 400, headers)

    client = bigquery.Client(project=PROJECT_ID)

    query = """
    WITH 
    -- 1. Resolve Antibody Serotypes into a single array
    resolved_antibodies AS (
      SELECT ARRAY_AGG(DISTINCT allele) AS arr
      FROM UNNEST(@input_alleles) AS val
      LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m ON val = m.serotype
      CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS allele
    ),
    
    -- 2. Resolve Recipient Serotypes into a single array
    resolved_recipient AS (
      SELECT ARRAY_AGG(DISTINCT allele) AS arr
      FROM UNNEST(@recipient_hla) AS val
      LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m ON val = m.serotype
      CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS allele
    ),

    -- 3. Resolve Donor Serotypes into a single array
    resolved_donor AS (
      SELECT ARRAY_AGG(DISTINCT allele) AS arr
      FROM UNNEST(@donor_hla) AS val
      LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m ON val = m.serotype
      CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS allele
    ),

    -- Pre-filter rows
    filtered_rows AS (
      SELECT t.epitope_name, t.alleles, t.required_alleles, t.theoretical, ra.arr AS user_arr, rr.arr AS recipient_arr, rd.arr AS donor_arr
      FROM `epitopefinder-458404`.epitopes.HLA_data AS t
      CROSS JOIN resolved_antibodies AS ra
      CROSS JOIN resolved_recipient AS rr
      CROSS JOIN resolved_donor AS rd
      WHERE EXISTS (
        SELECT 1 FROM UNNEST(t.alleles) AS a
        WHERE a IN UNNEST(ra.arr)
      )
    ),
    
    matches AS (
      SELECT
        t.epitope_name AS `Epitope Name`,
        t.theoretical AS `Theoretical`,
        EXISTS(SELECT 1 FROM UNNEST(t.alleles) AS a WHERE a IN UNNEST(t.recipient_arr)) AS cached_hasS,
        EXISTS(SELECT 1 FROM UNNEST(t.alleles) AS a WHERE a IN UNNEST(t.donor_arr)) AS cached_hasD,
        ARRAY(
          SELECT a FROM UNNEST(t.alleles) AS a
          WHERE a IN UNNEST(t.user_arr)
        ) AS `Positive Matches`,
        ARRAY(
          SELECT ra FROM UNNEST(t.required_alleles) AS ra
          WHERE
            ra IS NOT NULL AND
            ra != '' AND
            ra NOT IN UNNEST(t.user_arr)
        ) AS `Missing Required Alleles`,
        t.recipient_arr -- pass it through
      FROM
        filtered_rows AS t
    )
    
    SELECT
      * EXCEPT(recipient_arr),
      (SELECT arr FROM resolved_antibodies) AS expanded_input_alleles,
      CAST(ARRAY_LENGTH(`Positive Matches`) AS INT64) AS `Number of Positive Matches`,
      CAST(ARRAY_LENGTH(`Missing Required Alleles`) AS INT64) AS `Number of Missing Required Alleles`,
      
      (
        SELECT COUNT(1) 
        FROM UNNEST(`Positive Matches`) AS pm
        WHERE pm IN UNNEST(m.recipient_arr)
      ) AS `Self_Match_Count`
    FROM
      matches AS m
    ORDER BY
      -- RANKING LOGIC:
      `Self_Match_Count` ASC,              -- 1. Least "S" on top
      `Number of Positive Matches` DESC,   -- 2. More Positive matches on top
      `Number of Missing Required Alleles` ASC; -- 3. Less Negative matches on top
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ArrayQueryParameter("input_alleles", "STRING", input_alleles),
            bigquery.ArrayQueryParameter("recipient_hla", "STRING", recipient_hla),
            bigquery.ArrayQueryParameter("donor_hla", "STRING", donor_hla),
        ]
    )

    try:
        query_job = client.query(query, job_config=job_config)
        results = [dict(row) for row in query_job.result()]
        return (results, 200, headers)
    except Exception as e:
        logger.error(f"Error querying BigQuery: {e}")
        return (f"Internal Server Error: Query failed. {str(e)}", 500, headers)
