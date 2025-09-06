DECLARE input_alleles ARRAY<STRING>;
SET input_alleles = ["C*01:02", "B*08:01", "A*01:01"];
#replace this bit to be parameterized with front end

CREATE OR REPLACE TABLE `epitopefinder-458404`.epitopes.output AS
WITH user_alleles AS (
  SELECT allele FROM UNNEST(input_alleles) AS allele
),

matches AS ( #temp table for comparison
  SELECT
    t.epitope_id AS `Epitope ID`,
    t.epitope_name AS `Epitope Name`,
    t.locus AS Locus,
    ARRAY(
      SELECT allele FROM UNNEST(t.alleles) AS allele
      WHERE allele IN (SELECT allele FROM user_alleles)
    ) AS `Positive Matches`,
    ARRAY(
      SELECT required_allele FROM UNNEST(t.required_alleles) AS required_allele
      WHERE
        required_allele IS NOT NULL AND
        required_allele != '' AND
        required_allele NOT IN (SELECT allele FROM user_alleles)
    ) AS `Missing Required Alleles`
  FROM
    `epitopefinder-458404`.epitopes.HLA_data AS t
)

#load output table (may or may not be used, can create mismatches if multiple users use the service)
SELECT
  `Epitope ID`,
  `Epitope Name`,
  Locus,
  `Positive Matches`,
  CAST(ARRAY_LENGTH(`Positive Matches`) AS INT64) AS `Number of Positive Matches`,
  `Missing Required Alleles`,
  CAST(ARRAY_LENGTH(`Missing Required Alleles`) AS INT64) AS `Number of Missing Required Alleles`
FROM
  matches
ORDER BY
  `Number of Positive Matches` DESC,
  `Number of Missing Required Alleles` ASC;
