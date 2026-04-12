from google.cloud import bigquery
import json

PROJECT_ID = "epitopefinder-458404"

def test_expansion_logic():
    client = bigquery.Client(project=PROJECT_ID)
    
    # Test alleles
    input_alleles = ["A*02:01"] # Main search
    recipient_hla = ["A2"]      # Recipient as serotype (Intersection)
    donor_hla = ["A2"]          # Donor as serotype (Union)

    print(f"Testing with Input: {input_alleles}, Recipient: {recipient_hla}, Donor: {donor_hla}")

    query = """
    WITH 
    -- 1. Resolve Antibody Serotypes into a single array (Union for search columns)
    resolved_antibodies AS (
      SELECT ARRAY_AGG(DISTINCT allele IGNORE NULLS) AS arr
      FROM (
        SELECT expanded_allele as allele
        FROM UNNEST(@input_alleles) AS val
        LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m 
          ON REGEXP_REPLACE(REPLACE(val, '-', ''), r'^([a-zA-Z]+)0+', r'\\1') = 
             REGEXP_REPLACE(REPLACE(m.serotype, '-', ''), r'^([a-zA-Z]+)0+', r'\\1')
        CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS expanded_allele
      )
      WHERE allele LIKE '%*%'
    ),
    
    -- 2. Recipient Groups (for Intersection logic)
    recipient_groups AS (
      SELECT 
        val as original_input,
        ARRAY_AGG(DISTINCT expanded_allele IGNORE NULLS) as expanded_alleles
      FROM (
        SELECT val, expanded_allele
        FROM UNNEST(@recipient_hla) AS val
        LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m 
          ON REGEXP_REPLACE(REPLACE(val, '-', ''), r'^([a-zA-Z]+)0+', r'\\1') = 
             REGEXP_REPLACE(REPLACE(m.serotype, '-', ''), r'^([a-zA-Z]+)0+', r'\\1')
        CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS expanded_allele
      )
      WHERE expanded_allele LIKE '%*%'
      GROUP BY val
    ),

    -- 3. Donor Groups (for Union logic)
    donor_groups AS (
      SELECT 
        val as original_input,
        ARRAY_AGG(DISTINCT expanded_allele IGNORE NULLS) as expanded_alleles
      FROM (
        SELECT val, expanded_allele
        FROM UNNEST(@donor_hla) AS val
        LEFT JOIN `epitopefinder-458404`.epitopes.serotype_mapping AS m 
          ON REGEXP_REPLACE(REPLACE(val, '-', ''), r'^([a-zA-Z]+)0+', r'\\1') = 
             REGEXP_REPLACE(REPLACE(m.serotype, '-', ''), r'^([a-zA-Z]+)0+', r'\\1')
        CROSS JOIN UNNEST(CASE WHEN m.alleles IS NOT NULL THEN m.alleles ELSE [val] END) AS expanded_allele
      )
      WHERE expanded_allele LIKE '%*%'
      GROUP BY val
    ),

    -- 4. Flattened recipient list for allele-level matching (ranking)
    recipient_alleles_flat AS (
      SELECT ARRAY_AGG( ma IGNORE NULLS) as arr FROM (SELECT DISTINCT ma FROM recipient_groups, UNNEST(expanded_alleles) ma)
    ),

    -- Pre-filter rows
    filtered_rows AS (
      SELECT t.epitope_name, t.alleles, t.required_alleles, t.theoretical, ra.arr AS user_arr
      FROM `epitopefinder-458404`.epitopes.HLA_data AS t
      CROSS JOIN resolved_antibodies AS ra
      WHERE EXISTS (
        SELECT 1 FROM UNNEST(t.alleles) AS a
        WHERE a IN UNNEST(ra.arr)
      )
    ),
    
    matches AS (
      SELECT
        t.epitope_name AS epitope,
        -- cached_hasS: True if epitope is present in ALL alleles of AT LEAST ONE recipient input (Intersection)
        EXISTS (
          SELECT 1 FROM recipient_groups rg
          WHERE (
            SELECT COUNT(1) FROM UNNEST(rg.expanded_alleles) ma 
            WHERE ma IN UNNEST(t.alleles)
          ) = ARRAY_LENGTH(rg.expanded_alleles)
        ) AS has_S,
        -- cached_hasD: True if epitope is present in ANY allele of AT LEAST ONE donor input (Union)
        EXISTS (
          SELECT 1 FROM donor_groups dg
          WHERE EXISTS (
            SELECT 1 FROM UNNEST(dg.expanded_alleles) ma
            WHERE ma IN UNNEST(t.alleles)
          )
        ) AS has_D
      FROM
        filtered_rows AS t
    )
    
    SELECT * FROM matches
    LIMIT 20
    """
    
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ArrayQueryParameter("input_alleles", "STRING", input_alleles),
            bigquery.ArrayQueryParameter("recipient_hla", "STRING", recipient_hla),
            bigquery.ArrayQueryParameter("donor_hla", "STRING", donor_hla),
        ]
    )

    try:
        query_job = client.query(query, job_config=job_config)
        results = query_job.result()
        print("\n--- Results (Top 20 matches for A*02:01) ---")
        print(f"{'Epitope':<15} | {'Recipient (S)':<15} | {'Donor (D)':<15}")
        print("-" * 50)
        for row in results:
            print(f"{row.epitope:<15} | {str(row.has_S):<15} | {str(row.has_D):<15}")
    except Exception as e:
        print(f"Error querying BigQuery: {e}")

if __name__ == "__main__":
    test_expansion_logic()
