import functions_framework
from google.cloud import bigquery
import os


@functions_framework.http
def fetch_bq_epitopes(request):

    # Set CORS headers for the preflight request
    if request.method == "OPTIONS":
        headers = {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Max-Age": "3600",
        }
        return ("", 204, headers)

    # Set CORS headers for the main request
    headers = {"Access-Control-Allow-Origin": "*"}

    request_json = request.get_json(silent=True)

    if not request_json or "input_alleles" not in request_json:
        return ("Bad Request: `input_alleles` array is required.", 400, headers)

    input_alleles = request_json["input_alleles"]

    query = """
    WITH user_alleles AS (
      SELECT allele FROM UNNEST(@input_alleles) AS allele
    ),
    
    matches AS (
      SELECT
        t.epitope_id AS `Epitope ID`,
        t.epitope_name AS `Epitope Name`,
        t.locus AS Locus,
        ARRAY(
          SELECT allele FROM UNNEST(t.alleles) AS allele
          WHERE allele IN (SELECT allele FROM user_alleles)
        ) AS `Positive Matches`,
        ARRAY(
          SELECT required_allele FROM UNNEST(t.required_alleles) AS required_allele
          WHERE
            required_allele IS NOT NULL AND
            required_allele != '' AND
            required_allele NOT IN (SELECT allele FROM user_alleles)
        ) AS `Missing Required Alleles`
      FROM
        `epitopefinder-458404`.epitopes.HLA_data AS t
    )
    
    SELECT
      `Epitope ID`,
      `Epitope Name`,
      Locus,
      `Positive Matches`,
      CAST(ARRAY_LENGTH(`Positive Matches`) AS INT64) AS `Number of Positive Matches`,
      `Missing Required Alleles`,
      CAST(ARRAY_LENGTH(`Missing Required Alleles`) AS INT64) AS `Number of Missing Required Alleles`
    FROM
      matches
    ORDER BY
      `Number of Positive Matches` DESC,
      `Number of Missing Required Alleles` ASC;
    """

    project_id = os.environ.get("EpitopeFinder", "epitopefinder-458404")

    try:
        client = bigquery.Client(project=project_id)

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ArrayQueryParameter("input_alleles", "STRING", input_alleles),
            ],
        )

        query_job = client.query(query, job_config=job_config)

        rows = query_job.result()

        results = [dict(row) for row in rows]

        return (results, 200, headers)

    except Exception as e:
        print(f"An error occurred: {e}")
        return (f"An error occurred: {str(e)}", 500, headers)
