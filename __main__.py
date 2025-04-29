from epitope import *

if __name__ == "__main__":
    extracted_data = json.dumps(
        extract_table_data(
            base_url,
        ),
        indent=2,
    )
    print_to_file(extracted_data)
