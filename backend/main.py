import functions_framework
from google.cloud import bigquery
import os
import logging
import json

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
    -- 1. Resolve Antibody Serotypes into a single flattened list
    antibody_flat AS (
      SELECT DISTINCT expanded_allele as a
      FROM UNNEST(@input_alleles) AS val
      LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m 
        ON REGEXP_REPLACE(REPLACE(val, '-', ''), r'^([a-zA-Z]+)0+', r'\\1') = 
           REGEXP_REPLACE(REPLACE(m.serotype, '-', ''), r'^([a-zA-Z]+)0+', r'\\1')
      CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS expanded_allele
      WHERE expanded_allele LIKE '%*%'
    ),

    -- 2. Resolve Recipient Serotypes into Groups
    recipient_groups AS (
      SELECT val, ARRAY_LENGTH(ARRAY_AGG(DISTINCT expanded_allele)) as target_count, ARRAY_AGG(DISTINCT expanded_allele) as alleles
      FROM UNNEST(@recipient_hla) AS val
      LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m 
        ON REGEXP_REPLACE(REPLACE(val, '-', ''), r'^([a-zA-Z]+)0+', r'\\1') = 
           REGEXP_REPLACE(REPLACE(m.serotype, '-', ''), r'^([a-zA-Z]+)0+', r'\\1')
      CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS expanded_allele
      WHERE expanded_allele LIKE '%*%'
      GROUP BY val
    ),
    recipient_flat AS ( SELECT val, a FROM recipient_groups, UNNEST(alleles) a ),

    -- 3. Resolve Donor Serotypes into Groups
    donor_groups AS (
      SELECT val, ARRAY_LENGTH(ARRAY_AGG(DISTINCT expanded_allele)) as target_count, ARRAY_AGG(DISTINCT expanded_allele) as alleles
      FROM UNNEST(@donor_hla) AS val
      LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m 
        ON REGEXP_REPLACE(REPLACE(val, '-', ''), r'^([a-zA-Z]+)0+', r'\\1') = 
           REGEXP_REPLACE(REPLACE(m.serotype, '-', ''), r'^([a-zA-Z]+)0+', r'\\1')
      CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS expanded_allele
      WHERE expanded_allele LIKE '%*%'
      GROUP BY val
    ),
    donor_flat AS ( SELECT val, a FROM donor_groups, UNNEST(alleles) a ),

    -- 4. Calculate matches per recipient group
    recipient_matches AS (
      SELECT t.epitope_name, LOGICAL_OR(match_count = rg.target_count) as has_S
      FROM (
        SELECT t2.epitope_name, rf.val, COUNT(DISTINCT ta) as match_count
        FROM `epitopefinder-458404`.epitopes.HLA_data t2
        CROSS JOIN UNNEST(t2.alleles) ta
        JOIN recipient_flat rf ON ta = rf.a
        GROUP BY 1, 2
      ) sm
      JOIN recipient_groups rg ON sm.val = rg.val
      GROUP BY 1
    ),

    -- 5. Calculate matches per donor group
    donor_matches AS (
      SELECT t.epitope_name, LOGICAL_OR(match_count = dg.target_count) as has_D
      FROM (
        SELECT t2.epitope_name, df.val, COUNT(DISTINCT ta) as match_count
        FROM `epitopefinder-458404`.epitopes.HLA_data t2
        CROSS JOIN UNNEST(t2.alleles) ta
        JOIN donor_flat df ON ta = df.a
        GROUP BY 1, 2
      ) sm
      JOIN donor_groups dg ON sm.val = dg.val
      GROUP BY 1
    ),

    -- 6. Identify matching epitopes for search and calculate Pos matches
    base_matches AS (
      SELECT 
        t.epitope_name,
        t.theoretical,
        t.required_alleles,
        ARRAY_AGG(DISTINCT ta IGNORE NULLS) as positive_matches,
        COUNT(DISTINCT CASE WHEN rf.a IS NOT NULL THEN ta END) as self_match_count
      FROM `epitopefinder-458404`.epitopes.HLA_data t
      CROSS JOIN UNNEST(t.alleles) ta
      JOIN antibody_flat af ON ta = af.a
      LEFT JOIN recipient_flat rf ON ta = rf.a
      GROUP BY 1, 2, 3
    ),

    -- 7. Final Assembly
    SELECT 
      t.epitope_name AS `Epitope Name`,
      t.theoretical AS `Theoretical`,
      COALESCE(rm.has_S, false) as cached_hasS,
      COALESCE(dm.has_D, false) as cached_hasD,
      t.positive_matches AS `Positive Matches`,
      ARRAY(
        SELECT ra FROM UNNEST(t.required_alleles) ra 
        WHERE ra IS NOT NULL AND ra != '' AND ra NOT IN (SELECT a FROM antibody_flat)
      ) as `Missing Required Alleles`,
      CAST(ARRAY_LENGTH(t.positive_matches) AS INT64) AS `Number of Positive Matches`,
      CAST((SELECT COUNT(1) FROM UNNEST(t.required_alleles) ra WHERE ra IS NOT NULL AND ra != '' AND ra NOT IN (SELECT a FROM antibody_flat)) AS INT64) AS `Number of Missing Required Alleles`,
      COALESCE(t.self_match_count, 0) as `Self_Match_Count`
    FROM base_matches t
    LEFT JOIN recipient_matches rm ON t.epitope_name = rm.epitope_name
    LEFT JOIN donor_matches dm ON t.epitope_name = dm.epitope_name
    ORDER BY
      `Self_Match_Count` ASC,
      `Number of Positive Matches` DESC,
      `Number of Missing Required Alleles` ASC;
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
