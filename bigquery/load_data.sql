INSERT INTO `epitopefinder-458404`.epitopes.HLA_data (
    epitope_id,
    epitope_name,
    description,
    alleles, 
    required_alleles,
    locus 
)
SELECT
    ID AS epitope_id,
    Name AS epitope_name,
    Description AS description,
    Alleles, 
    `Required Alleles` ,
    'ABC' AS locus
FROM
    `epitopefinder-458404`.epitopes.raw_ABC;

INSERT INTO `epitopefinder-458404`.epitopes.HLA_data (
    epitope_id,
    epitope_name,
    description,
    alleles, 
    required_alleles,
    locus
)
SELECT
    ID AS epitope_id,
    Name AS epitope_name,
    Description AS description,
    Alleles,
    `Required Alleles`,
    'DQ' AS locus
FROM
    `epitopefinder-458404`.epitopes.raw_DQ;

INSERT INTO `epitopefinder-458404`.epitopes.HLA_data (
    epitope_id,
    epitope_name,
    description,
    alleles, 
    required_alleles,
    locus 
)
SELECT
    ID AS epitope_id,
    Name AS epitope_name,
    Description AS description,
    Alleles,
    `Required Alleles`,
    'DRB' AS locus
FROM
    `epitopefinder-458404`.epitopes.raw_DRB;

INSERT INTO `epitopefinder-458404`.epitopes.HLA_data (
    epitope_id,
    epitope_name,
    description,
    alleles, 
    required_alleles,
    locus 
)
SELECT
    ID AS epitope_id,
    Name AS epitope_name,
    Description AS description,
    Alleles,
    `Required Alleles`,
    'MICA' AS locus
FROM
    `epitopefinder-458404`.epitopes.raw_MICA;

INSERT INTO `epitopefinder-458404`.epitopes.HLA_data (
    epitope_id,
    epitope_name,
    description,
    alleles, 
    required_alleles,
    locus 
)
SELECT
    ID AS epitope_id,
    Name AS epitope_name,
    Description AS description,
    Alleles,
    `Required Alleles`,
    'DP' AS locus
FROM
    `epitopefinder-458404`.epitopes.raw_DP;
