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

    # Fetch Allele List
    logger.info("Loading allele list from BigQuery...")
    try:
        query = "SELECT allele_name FROM `epitopefinder-458404`.epitopes.allele_list ORDER BY allele_name"
        query_job = client.query(query)
        # Use tuple for immutable, smaller cache
        ALLELE_CACHE = tuple(row["allele_name"] for row in query_job.result())
        logger.info(f"Successfully loaded {len(ALLELE_CACHE)} allele names.")
    except Exception as e:
        logger.error(f"Error loading allele list from BigQuery: {e}")
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
    user_antibodies AS (
      SELECT allele FROM UNNEST(@input_alleles) AS allele
    ),
    
    recipient_hla_list AS (
      SELECT allele FROM UNNEST(@recipient_hla) AS allele
    ),

    donor_hla_list AS (
      SELECT allele FROM UNNEST(@donor_hla) AS allele
    ),

    -- Pre-filter rows to only those with at least one antibody match
    filtered_rows AS (
      SELECT *
      FROM `epitopefinder-458404`.epitopes.HLA_data AS t
      WHERE EXISTS (
        SELECT 1 FROM UNNEST(t.alleles) AS a
        WHERE a IN (SELECT allele FROM user_antibodies)
      )
    ),
    
    matches AS (
      SELECT
        t.epitope_id AS `Epitope ID`,
        t.epitope_name AS `Epitope Name`,
        t.locus AS Locus,
        EXISTS(SELECT 1 FROM UNNEST(t.alleles) AS a WHERE a IN (SELECT allele FROM recipient_hla_list)) AS cached_hasS,
        EXISTS(SELECT 1 FROM UNNEST(t.alleles) AS a WHERE a IN (SELECT allele FROM donor_hla_list)) AS cached_hasD,
        ARRAY(
          SELECT allele FROM UNNEST(t.alleles) AS allele
          WHERE allele IN (SELECT allele FROM user_antibodies)
        ) AS `Positive Matches`,
        ARRAY(
          SELECT required_allele FROM UNNEST(t.required_alleles) AS required_allele
          WHERE
            required_allele IS NOT NULL AND
            required_allele != '' AND
            required_allele NOT IN (SELECT allele FROM user_antibodies)
        ) AS `Missing Required Alleles`
      FROM
        filtered_rows AS t
    )
    
    SELECT
      *,
      CAST(ARRAY_LENGTH(`Positive Matches`) AS INT64) AS `Number of Positive Matches`,
      CAST(ARRAY_LENGTH(`Missing Required Alleles`) AS INT64) AS `Number of Missing Required Alleles`,
      
      -- CALCULATION: How many "S" (Self) alleles are in the positive matches?
      (
        SELECT COUNT(1) 
        FROM UNNEST(`Positive Matches`) AS pm
        WHERE pm IN (SELECT allele FROM recipient_hla_list)
      ) AS `Self_Match_Count`
    FROM
      matches
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
