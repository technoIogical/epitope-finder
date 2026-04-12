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
    -- 1. Resolve Antibody Serotypes into a single flattened list with original values
    antibody_flat AS (
      SELECT DISTINCT val, expanded_allele as a
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

    -- 3. Resolve Donor Serotypes into a single flattened list
    donor_flat AS (
      SELECT DISTINCT expanded_allele as a
      FROM UNNEST(@donor_hla) AS val
      LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m 
        ON REGEXP_REPLACE(REPLACE(val, '-', ''), r'^([a-zA-Z]+)0+', r'\\1') = 
           REGEXP_REPLACE(REPLACE(m.serotype, '-', ''), r'^([a-zA-Z]+)0+', r'\\1')
      CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS expanded_allele
      WHERE expanded_allele LIKE '%*%'
    ),

    -- 4. Calculate all matches in a single aggregation pass for performance and de-correlation
    matched_results AS (
      SELECT 
        t.epitope_name,
        t.theoretical,
        t.required_alleles,
        -- has_D: Union logic (Any donor allele matches)
        LOGICAL_OR(df.a IS NOT NULL) as cached_hasD,
        -- matches_by_group: For recipient intersection logic
        ARRAY_AGG(STRUCT(rf.val as group_name, rf.a as matched_allele) IGNORE NULLS) as recipient_matches,
        -- positive_matches: Return the original search term (val) to avoid column explosion
        ARRAY_AGG(DISTINCT af.val IGNORE NULLS) as positive_matches,
        -- count how many of the positive matches are also in the recipient typing (for ranking)
        COUNT(DISTINCT CASE WHEN af.a IS NOT NULL AND rf.a IS NOT NULL THEN ta END) as self_match_count
      FROM `epitopefinder-458404`.epitopes.HLA_data t
      CROSS JOIN UNNEST(t.alleles) ta
      LEFT JOIN antibody_flat af ON ta = af.a
      LEFT JOIN recipient_flat rf ON ta = rf.a
      LEFT JOIN donor_flat df ON ta = df.a
      GROUP BY 1, 2, 3
      HAVING COUNT(af.a) > 0 -- Only epitopes matching search columns
    )

    -- 5. Final Assembly with Intersection calculation
    SELECT 
      t.epitope_name AS `Epitope Name`,
      t.theoretical AS `Theoretical`,
      -- cached_hasS: True if epitope has ALL alleles of AT LEAST ONE recipient group
      EXISTS (
        SELECT 1 FROM recipient_groups rg
        WHERE (
          SELECT COUNT(DISTINCT m.matched_allele) 
          FROM UNNEST(t.recipient_matches) m 
          WHERE m.group_name = rg.val
        ) = rg.target_count
      ) as cached_hasS,
      t.cached_hasD,
      t.positive_matches AS `Positive Matches`,
      ARRAY(
        SELECT ra FROM UNNEST(t.required_alleles) ra 
        WHERE ra IS NOT NULL AND ra != '' AND ra NOT IN (SELECT a FROM antibody_flat)
      ) as `Missing Required Alleles`,
      CAST(ARRAY_LENGTH(t.positive_matches) AS INT64) AS `Number of Positive Matches`,
      CAST((SELECT COUNT(1) FROM UNNEST(t.required_alleles) ra WHERE ra IS NOT NULL AND ra != '' AND ra NOT IN (SELECT a FROM antibody_flat)) AS INT64) AS `Number of Missing Required Alleles`,
      t.self_match_count AS `Self_Match_Count`
    FROM matched_results t
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
