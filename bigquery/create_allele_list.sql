-- Create or replace the allele_list table for autocomplete
CREATE OR REPLACE TABLE `epitopefinder-458404.epitopes.allele_list` AS
SELECT DISTINCT
    TRIM(allele) AS allele_name
FROM
    `epitopefinder-458404.epitopes.HLA_data`,
    UNNEST(alleles) AS allele
WHERE
    TRIM(allele) != ''
ORDER BY
    allele_name;
