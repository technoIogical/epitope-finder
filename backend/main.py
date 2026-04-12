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

    -- 4. Pre-identify matching epitopes to avoid processing the whole DB
    search_matches AS (
      SELECT DISTINCT t.epitope_name
      FROM `epitopefinder-458404`.epitopes.HLA_data t
      INNER JOIN UNNEST(t.alleles) ta
      INNER JOIN antibody_flat af ON ta = af.a
    ),

    -- 5. Calculate S matches (Intersection logic)
    s_status AS (
      SELECT sm.epitope_name, LOGICAL_OR(sm.match_count = rg.target_count) as has_S
      FROM (
        SELECT t.epitope_name, rf.val, COUNT(DISTINCT ta) as match_count
        FROM `epitopefinder-458404`.epitopes.HLA_data t
        JOIN search_matches sem ON t.epitope_name = sem.epitope_name
        INNER JOIN UNNEST(t.alleles) ta
        INNER JOIN recipient_flat rf ON ta = rf.a
        GROUP BY 1, 2
      ) sm
      JOIN recipient_groups rg ON sm.val = rg.val
      GROUP BY 1
    ),

    -- 6. Calculate D matches (Union logic)
    d_status AS (
      SELECT DISTINCT t.epitope_name, TRUE as has_D
      FROM `epitopefinder-458404`.epitopes.HLA_data t
      JOIN search_matches sem ON t.epitope_name = sem.epitope_name
      INNER JOIN UNNEST(t.alleles) ta
      INNER JOIN donor_flat df ON ta = df.a
    ),

    -- 7. Calculate Positive Matches and Self Match Count for ranking
    matched_data AS (
      SELECT 
        t.epitope_name, 
        ARRAY_AGG(DISTINCT CASE WHEN af.a IS NOT NULL THEN ta END IGNORE NULLS) as positive_matches,
        COUNT(DISTINCT CASE WHEN af.a IS NOT NULL AND rf.a IS NOT NULL THEN ta END) as self_match_count
      FROM `epitopefinder-458404`.epitopes.HLA_data t
      JOIN search_matches sem ON t.epitope_name = sem.epitope_name
      INNER JOIN UNNEST(t.alleles) ta
      LEFT JOIN antibody_flat af ON ta = af.a
      LEFT JOIN recipient_flat rf ON ta = rf.a
      GROUP BY 1
    ),

    -- 8. Calculate Missing Required Alleles
    missing_required AS (
      SELECT t.epitope_name, ARRAY_AGG(ra IGNORE NULLS) as missing
      FROM `epitopefinder-458404`.epitopes.HLA_data t
      JOIN search_matches sem ON t.epitope_name = sem.epitope_name
      INNER JOIN UNNEST(t.required_alleles) ra
      LEFT JOIN antibody_flat af ON ra = af.a
      WHERE ra IS NOT NULL AND ra != '' AND af.a IS NULL
      GROUP BY 1
    )

    -- 9. Final Assembly
    SELECT 
      t.epitope_name AS `Epitope Name`,
      t.theoretical AS `Theoretical`,
      COALESCE(ss.has_S, false) as cached_hasS,
      COALESCE(ds.has_D, false) as cached_hasD,
      COALESCE(md.positive_matches, []) as `Positive Matches`,
      COALESCE(mr.missing, []) as `Missing Required Alleles`,
      CAST(ARRAY_LENGTH(COALESCE(md.positive_matches, [])) AS INT64) AS `Number of Positive Matches`,
      CAST(ARRAY_LENGTH(COALESCE(mr.missing, [])) AS INT64) AS `Number of Missing Required Alleles`,
      COALESCE(md.self_match_count, 0) as `Self_Match_Count`
    FROM `epitopefinder-458404`.epitopes.HLA_data t
    JOIN search_matches sem ON t.epitope_name = sem.epitope_name
    LEFT JOIN s_status ss ON t.epitope_name = ss.epitope_name
    LEFT JOIN d_status ds ON t.epitope_name = ds.epitope_name
    LEFT JOIN matched_data md ON t.epitope_name = md.epitope_name
    LEFT JOIN missing_required mr ON t.epitope_name = mr.epitope_name
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
