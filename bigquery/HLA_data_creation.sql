CREATE OR REPLACE TABLE epitopefinder-458404.epitopes.HLA_data (
    epitope_id INTEGER OPTIONS(description="Epitope ID"),
    epitope_name STRING OPTIONS(description="Name"),
    description STRING OPTIONS(description="Description"), 
    alleles ARRAY<STRING> OPTIONS(description="List of all alleles that can bind to this epitope"),
    required_alleles ARRAY<STRING> OPTIONS(description="List of alleles that are required for this epitope to function"),
    locus STRING OPTIONS(description="locus of the allele ex. HLA-ABC, HLA-DP, etc.")
);