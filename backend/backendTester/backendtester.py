import requests
import json


def run_cloud_function_query(alleles):
    
    cloud_function_url = "https://epitope-server-998762220496.europe-west1.run.app/"
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
    alleles_to_query = ["C01:02", "C01:03", "C02:02", "C02:10", "C05:01", "C06:02", "C07:01", "C07:02", "C07:04", "C08:01", "C08:02", "C08:03", "C08:04", "C12:02", "C12:03", "C14:02", "C14:03", "C15:02", "C15:05", "C16:01", "C16:02", "C18:01", "C*18:02"]

    epitope_data = run_cloud_function_query(alleles_to_query)

    if epitope_data:
        save_results_to_json_file(epitope_data, "epitope_data.json")
    else:
        print("Failed to get epitope data.")
