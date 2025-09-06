import os
import json

file_path = os.path.dirname(os.path.abspath(__file__))
storage_path = os.path.join(file_path, "extracted")


def print_to_file(extracted_data, target):
    if not os.path.exists(storage_path):
        os.makedirs(storage_path)

    output_file_path = os.path.join(
        storage_path, f"epitope_output{target}.json"
    )  # Note: You can still use .json extension
    with open(output_file_path, "w", encoding="utf-8") as f:  # Ensure UTF-8 encoding
        for record in extracted_data:  # Iterate through the list of dictionaries
            json.dump(record, f, ensure_ascii=False)  # Write each dictionary as JSON
            f.write("\n")  # Add a newline character
