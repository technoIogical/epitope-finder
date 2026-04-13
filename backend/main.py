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
    -- 1. Resolve Antibody Serotypes into a single flattened list of high-res alleles
    antibody_flat AS (
      SELECT DISTINCT expanded_allele as a
      FROM UNNEST(@input_alleles) AS val
      LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m 
        ON REGEXP_REPLACE(REPLACE(val, '-', ''), r'^([a-zA-Z]+)0+', r'\\1') = 
           REGEXP_REPLACE(REPLACE(m.serotype, '-', ''), r'^([a-zA-Z]+)0+', r'\\1')
      CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS expanded_allele
      WHERE expanded_allele LIKE '%*%'
    ),

    -- 2. Resolve Recipient Serotypes into a flat list (treat as if typed one by one)
    recipient_flat AS (
      SELECT DISTINCT expanded_allele as a
      FROM UNNEST(@recipient_hla) AS val
      LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m 
        ON REGEXP_REPLACE(REPLACE(val, '-', ''), r'^([a-zA-Z]+)0+', r'\\1') = 
           REGEXP_REPLACE(REPLACE(m.serotype, '-', ''), r'^([a-zA-Z]+)0+', r'\\1')
      CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS expanded_allele
      WHERE expanded_allele LIKE '%*%'
    ),

    -- 3. Resolve Donor Serotypes into a flat list
    donor_flat AS (
      SELECT DISTINCT expanded_allele as a
      FROM UNNEST(@donor_hla) AS val
      LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m 
        ON REGEXP_REPLACE(REPLACE(val, '-', ''), r'^([a-zA-Z]+)0+', r'\\1') = 
           REGEXP_REPLACE(REPLACE(m.serotype, '-', ''), r'^([a-zA-Z]+)0+', r'\\1')
      CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS expanded_allele
      WHERE expanded_allele LIKE '%*%'
    ),

    -- 4. Main matching logic: Perform a single pass join across all sets
    matches AS (
      SELECT 
        t.epitope_name,
        t.theoretical,
        t.required_alleles,
        -- has_S: True if epitope is in ANY recipient allele (per instructions to treat as one-by-one input)
        LOGICAL_OR(rf.a IS NOT NULL) as has_S,
        -- has_D: True if epitope is in ANY donor allele
        LOGICAL_OR(df.a IS NOT NULL) as has_D,
        -- positive_matches: Return expanded high-res alleles for columns
        ARRAY_AGG(DISTINCT af.a IGNORE NULLS) as positive_matches,
        -- self_match_count: count matching search alleles for ranking
        COUNT(DISTINCT CASE WHEN af.a IS NOT NULL AND rf.a IS NOT NULL THEN ta END) as self_match_count
      FROM `epitopefinder-458404`.epitopes.HLA_data t
      CROSS JOIN UNNEST(t.alleles) ta
      LEFT JOIN antibody_flat af ON ta = af.a
      LEFT JOIN recipient_flat rf ON ta = rf.a
      LEFT JOIN donor_flat df ON ta = df.a
      GROUP BY 1, 2, 3
      HAVING COUNT(af.a) > 0 -- Must match at least one searched allele
    ),

    -- 5. Calculate Missing Required Alleles
    missing_data AS (
      SELECT 
        m.epitope_name, 
        ARRAY_AGG(ra IGNORE NULLS) as missing
      FROM matches m
      JOIN `epitopefinder-458404`.epitopes.HLA_data t ON m.epitope_name = t.epitope_name
      CROSS JOIN UNNEST(t.required_alleles) ra
      LEFT JOIN antibody_flat af ON ra = af.a
      WHERE ra IS NOT NULL AND ra != '' AND af.a IS NULL
      GROUP BY 1
    ),

    -- 6. Global lists of expanded alleles for frontend
    antibody_alleles AS ( SELECT ARRAY_AGG(a) as arr FROM antibody_flat ),
    recipient_alleles AS ( SELECT ARRAY_AGG(a) as arr FROM recipient_flat ),
    donor_alleles AS ( SELECT ARRAY_AGG(a) as arr FROM donor_flat ),

    final_results AS (
      SELECT 
        m.epitope_name AS `Epitope Name`,
        m.theoretical AS `Theoretical`,
        m.has_S as cached_hasS,
        m.has_D as cached_hasD,
        m.positive_matches AS `Positive Matches`,
        COALESCE(md.missing, []) as `Missing Required Alleles`,
        m.self_match_count AS `Self_Match_Count`,
        aa.arr as expanded_input_alleles,
        ra.arr as expanded_recipient_alleles,
        da.arr as expanded_donor_alleles
      FROM matches m
      CROSS JOIN antibody_alleles aa
      CROSS JOIN recipient_alleles ra
      CROSS JOIN donor_alleles da
      LEFT JOIN missing_data md ON m.epitope_name = md.epitope_name
    )

    -- 7. Final Selection with scalar functions
    SELECT
      *,
      CAST(ARRAY_LENGTH(`Positive Matches`) AS INT64) AS `Number of Positive Matches`,
      CAST(ARRAY_LENGTH(`Missing Required Alleles`) AS INT64) AS `Number of Missing Required Alleles`
    FROM final_results
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
