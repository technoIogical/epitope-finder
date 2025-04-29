import os

file_path = os.path.dirname(os.path.abspath(__file__))
storage_path = os.path.join(file_path, "extracted")


def print_to_file(extracted_data, target):
    if not os.path.exists(storage_path):
        os.makedirs(storage_path)

    output_file_path = os.path.join(storage_path, f"epitope_output{target}.json")
    with open(output_file_path, "w") as f:
        f.write(extracted_data)


print_to_file("buh", "ABC")
