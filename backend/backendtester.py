import requests
import json


def run_cloud_function_query(alleles):
    """
    Sends a parameterized request to the Cloud Function and returns the results.
    """
    cloud_function_url = "https://epitope-server-998762220496.europe-west1.run.app"
    payload = {"input_alleles": alleles}
    headers = {"Content-Type": "application/json"}

    try:
        response = requests.post(
            cloud_function_url, data=json.dumps(payload), headers=headers
        )
        response.raise_for_status()
        results = response.json()
        return results

    except requests.exceptions.RequestException as err:
        print(f"An error occurred: {err}")
    except json.JSONDecodeError:
        print("Failed to decode JSON from the response.")

    return None


def save_results_to_json_file(results, filename):
    """
    Saves the results as a formatted JSON string to a specified file.
    """
    if not results:
        print("No results to save.")
        return False

    try:
        with open(filename, "w") as f:
            json.dump(results, f, indent=2)
        print(f"Successfully saved data to '{filename}'")
        return True
    except IOError as e:
        print(f"Error saving file: {e}")

        return False


if __name__ == "__main__":
    alleles_to_query = ["A*01:01", "B*08:01", "C*01:02"]

    epitope_data = run_cloud_function_query(alleles_to_query)

    if epitope_data:
        save_results_to_json_file(epitope_data, "epitope_data.json")

        # Extract and print the Epitope IDs from the results
        epitope_ids = [item.get("Epitope ID") for item in epitope_data]
        # print("\nEpitope IDs retrieved:")
        epitope_ids.sort()
        print(epitope_ids)
    else:
        print("Failed to get epitope data.")
