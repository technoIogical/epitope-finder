import functions_framework
from google.cloud import bigquery
import os

@functions_framework.http
def fetch_bq_epitopes(request):
    # Set CORS headers
    if request.method == "OPTIONS":
        headers = {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST",
            "Access-Control-Allow-Headers": "Content-Type, Authorization",
            "Access-Control-Max-Age": "3600",
        }
        return ("", 204, headers)

    headers = {"Access-Control-Allow-Origin": "*"}

    request_json = request.get_json(silent=True)
    if request_json is None:
        return ("Bad Request: Request body must be valid JSON.", 400, headers)

    # We only strictly need 'input_alleles' (Antibodies) for the search now.
    # Recipient/Donor HLA will be handled visually on the frontend.
    input_alleles = request_json.get("input_alleles", [])

    if not input_alleles:
        return ("Bad Request: `input_alleles` array is required.", 400, headers)

    # Query: Find matches, but REMOVED the "WHERE NOT EXISTS" exclusion filter.
    query = """
    WITH 
    user_antibodies AS (
      SELECT allele FROM UNNEST(@input_alleles) AS allele
    ),
    
    matches AS (
      SELECT
        t.epitope_id AS `Epitope ID`,
        t.epitope_name AS `Epitope Name`,
        t.locus AS Locus,
        t.alleles AS All_Epitope_Alleles, 
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
        `epitopefinder-458404`.epitopes.HLA_data AS t
    )
    
    SELECT
      `Epitope ID`,
      `Epitope Name`,
      Locus,
      All_Epitope_Alleles, -- We return ALL alleles now so Frontend can check for S/D
      `Positive Matches`,
      CAST(ARRAY_LENGTH(`Positive Matches`) AS INT64) AS `Number of Positive Matches`,
      `Missing Required Alleles`,
      CAST(ARRAY_LENGTH(`Missing Required Alleles`) AS INT64) AS `Number of Missing Required Alleles`
    FROM
      matches
    WHERE
      ARRAY_LENGTH(`Positive Matches`) > 0
    ORDER BY
      `Number of Positive Matches` DESC,
      `Number of Missing Required Alleles` ASC;
    """

    project_id = "epitopefinder-458404"

    try:
        client = bigquery.Client(project=project_id)
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ArrayQueryParameter("input_alleles", "STRING", input_alleles),
            ],
        )
        query_job = client.query(query, job_config=job_config)
        results = [dict(row) for row in query_job.result()]
        return (results, 200, headers)

    except Exception as e:
        print(f"An error occurred: {e}")
        return (f"An error occurred: {str(e)}", 500, headers)