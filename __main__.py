from epitope import *
from targets import *
from savefiles import *


if __name__ == "__main__":
    targets = input_targets()

    for target in targets:
        base_url = "https://www.epregistry.com.br/databases/"
        extracted_data = extract_table_data(base_url, target) 
        if extracted_data:  
            print_to_file(extracted_data, target)  
        else:
            print(f"No data extracted for {target}, skipping")
