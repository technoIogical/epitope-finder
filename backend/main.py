import functions_framework
from google.cloud import bigquery
import os


@functions_framework.http
def fetch_bq_epitopes(request):
    if request.method == "OPTIONS":
        # Allows GET requests from any origin with the Content-Type
        # header and caches preflight response for an 3600s
        headers = {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET",
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

    project_id = os.environ.get("EpitopeFinder", "epitopefinder-458404")
    dataset_id = "epitopefinder-458404.epitopes"
    query_name = "output_logic"

    try:
        client = bigquery.Client(project=project_id)

        query_job_config = bigquery.QueryJobConfig(
            query=f"#bq:jobs:query:{project_id}.{dataset_id}.{query_name}",
            query_parameters=[
                bigquery.ArrayQueryParameter(
                    "patient_alleles", "STRING", patient_alleles
                ),
            ],
        )

        query_job = client.query(
            f"SELECT * FROM `{project_id}.{dataset_id}.{query_name}`",
            job_config=query_job_config,
        )
        rows = query_job.result()

        results = [dict(row) for row in rows]

        return (results, 200, headers)

    except Exception as e:
        print(f"An error occurred: {e}")
        return (f"An error occurred: {str(e)}", 500, headers)

    return ("Hello World!", 200, headers)
