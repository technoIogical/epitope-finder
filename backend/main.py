import functions_framework
from google.cloud import bigquery
import os

@functions_framework.http
def fetch_bq_epitopes(request):
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

    input_alleles = request_json.get("input_alleles", [])
    recipient_hla = request_json.get("recipient_hla", []) # <--- Needed for "S" sorting

    if not input_alleles:
        return ("Bad Request: `input_alleles` array is required.", 400, headers)

    query = """
    WITH 
    user_antibodies AS (
      SELECT allele FROM UNNEST(@input_alleles) AS allele
    ),
    
    recipient_hla_list AS (
      SELECT allele FROM UNNEST(@recipient_hla) AS allele
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
    WHERE
      ARRAY_LENGTH(`Positive Matches`) > 0
    ORDER BY
      -- RANKING LOGIC:
      `Self_Match_Count` ASC,              -- 1. Least "S" on top
      `Number of Positive Matches` DESC,   -- 2. More Positive matches on top
      `Number of Missing Required Alleles` ASC; -- 3. Less Negative matches on top
    """

    project_id = "epitopefinder-458404"

    try:
        client = bigquery.Client(project=project_id)
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ArrayQueryParameter("input_alleles", "STRING", input_alleles),
                bigquery.ArrayQueryParameter("recipient_hla", "STRING", recipient_hla),
            ],
        )
        query_job = client.query(query, job_config=job_config)
        results = [dict(row) for row in query_job.result()]
        return (results, 200, headers)

    except Exception as e:
        print(f"An error occurred: {e}")
        return (f"An error occurred: {str(e)}", 500, headers)