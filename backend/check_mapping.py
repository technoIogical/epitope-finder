from google.cloud import bigquery

def check_mapping():
    client = bigquery.Client(project="epitopefinder-458404")
    query = "SELECT * FROM `epitopefinder-458404`.epitopes.serotype_mapping WHERE serotype IN ('DP3', 'DP6', 'DP9', 'DP10', 'DP2')"
    
    try:
        results = client.query(query).result()
        print("--- Mapping Table Check ---")
        found = False
        for row in results:
            found = True
            print(f"Serotype: {row.serotype}, Alleles: {row.alleles}")
        if not found:
            print("No mappings found for these serotypes.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    check_mapping()
