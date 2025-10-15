import functions_framework
from google.cloud import bigquery
import os


@functions_framework.http
def fetch_bq_epitopes(request):
    """
    HTTP Cloud Function that runs a hard-coded BigQuery query.
    """
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

    # We will get the project_id from the environment variable, but for this
    # specific use case, we hardcode to the user's project ID for simplicity
    project_id = os.environ.get("EpitopeFinder", "epitopefinder-458404")

    # The saved query and its containing dataset
    dataset_id = "epitopes"
    query_name = "server_query"

    try:
        client = bigquery.Client(project=project_id)

        # This is the correct way to reference a saved query by its full path
        query_job = client.query(
            f"#bq:jobs:query:{project_id}.{dataset_id}.{query_name}",
            job_config=bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ArrayQueryParameter(
                        "input_alleles", "STRING", input_alleles
                    ),
                ],
            ),
        )

        rows = query_job.result()

        results = [dict(row) for row in rows]

        return (results, 200, headers)

    except Exception as e:
        print(f"An error occurred: {e}")
        return (f"An error occurred: {str(e)}", 500, headers)
