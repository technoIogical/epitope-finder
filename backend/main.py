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
    -- 1. Resolve Antibody Serotypes into a single array (Union for search columns)
    resolved_antibodies AS (
      SELECT ARRAY_AGG(DISTINCT allele IGNORE NULLS) AS arr
      FROM (
        SELECT expanded_allele as allele
        FROM UNNEST(@input_alleles) AS val
        LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m 
          ON REGEXP_REPLACE(REPLACE(val, '-', ''), r'^([a-zA-Z]+)0+', r'\\1') = 
             REGEXP_REPLACE(REPLACE(m.serotype, '-', ''), r'^([a-zA-Z]+)0+', r'\\1')
        CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS expanded_allele
      )
      WHERE allele LIKE '%*%'
    ),
    
    -- 2. Recipient Groups (Resolved into a STRUCT array for Intersection logic)
    recipient_resolved AS (
      SELECT ARRAY_AGG(STRUCT(expanded_alleles)) as r_groups
      FROM (
        SELECT 
          ARRAY_AGG(DISTINCT expanded_allele IGNORE NULLS) as expanded_alleles
        FROM (
          SELECT val, expanded_allele
          FROM UNNEST(@recipient_hla) AS val
          LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m 
            ON REGEXP_REPLACE(REPLACE(val, '-', ''), r'^([a-zA-Z]+)0+', r'\\1') = 
               REGEXP_REPLACE(REPLACE(m.serotype, '-', ''), r'^([a-zA-Z]+)0+', r'\\1')
          CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS expanded_allele
        )
        WHERE expanded_allele LIKE '%*%'
        GROUP BY val
      )
    ),

    -- 3. Donor Groups (Resolved into a STRUCT array for Union logic)
    donor_resolved AS (
      SELECT ARRAY_AGG(STRUCT(expanded_alleles)) as d_groups
      FROM (
        SELECT 
          ARRAY_AGG(DISTINCT expanded_allele IGNORE NULLS) as expanded_alleles
        FROM (
          SELECT val, expanded_allele
          FROM UNNEST(@donor_hla) AS val
          LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m 
            ON REGEXP_REPLACE(REPLACE(val, '-', ''), r'^([a-zA-Z]+)0+', r'\\1') = 
               REGEXP_REPLACE(REPLACE(m.serotype, '-', ''), r'^([a-zA-Z]+)0+', r'\\1')
          CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS expanded_allele
        )
        WHERE expanded_allele LIKE '%*%'
        GROUP BY val
      )
    ),

    -- 4. Flattened recipient list for allele-level matching (ranking)
    recipient_alleles_flat AS (
      SELECT ARRAY_AGG(DISTINCT ma IGNORE NULLS) as arr 
      FROM recipient_resolved rr, UNNEST(rr.r_groups) rg, UNNEST(rg.expanded_alleles) ma
    ),

    -- Pre-filter rows
    filtered_rows AS (
      SELECT t.epitope_name, t.alleles, t.required_alleles, t.theoretical, ra.arr AS user_arr
      FROM `epitopefinder-458404`.epitopes.HLA_data AS t
      CROSS JOIN resolved_antibodies AS ra
      WHERE EXISTS (
        SELECT 1 FROM UNNEST(t.alleles) AS a
        WHERE a IN UNNEST(ra.arr)
      )
    ),
    
    matches AS (
      SELECT
        t.epitope_name AS `Epitope Name`,
        t.theoretical AS `Theoretical`,
        -- cached_hasS: True if epitope is present in ALL alleles of AT LEAST ONE recipient input (Intersection)
        EXISTS (
          SELECT 1 FROM UNNEST(rr.r_groups) rg
          WHERE (
            SELECT COUNT(1) FROM UNNEST(rg.expanded_alleles) ma 
            WHERE ma IN UNNEST(t.alleles)
          ) = ARRAY_LENGTH(rg.expanded_alleles)
        ) AS cached_hasS,
        -- cached_hasD: True if epitope is present in ANY allele of AT LEAST ONE donor input (Union)
        EXISTS (
          SELECT 1 FROM UNNEST(dr.d_groups) dg
          WHERE EXISTS (
            SELECT 1 FROM UNNEST(dg.expanded_alleles) ma
            WHERE ma IN UNNEST(t.alleles)
          )
        ) AS cached_hasD,
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
        (SELECT arr FROM recipient_alleles_flat) as recipient_arr -- for ranking
      FROM
        filtered_rows AS t
      CROSS JOIN recipient_resolved rr
      CROSS JOIN donor_resolved dr
    )
    
    SELECT
      * EXCEPT(recipient_arr),
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
