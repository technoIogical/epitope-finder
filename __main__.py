from epitope import *
from targets import *
import json


if __name__ == "__main__":
    targets = input_targets()

    for target in targets:
        base_url = "https://www.epregistry.com.br/databases/"
        extracted_data = json.dumps(
            extract_table_data(base_url, target),
            indent=2,
        )
        print_to_file(extracted_data, target)
