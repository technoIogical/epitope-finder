TRUNCATE TABLE `epitopefinder-458404`.epitopes.HLA_data;

    INSERT INTO `epitopefinder-458404`.epitopes.HLA_data (
        epitope_id,
        epitope_name,
        description,
        alleles, 
        required_alleles,
        locus,
        theoretical
    )
    SELECT
        ID AS epitope_id,
        Name AS epitope_name,
        Description AS description,
        Alleles, 
        `Required Alleles`,
        'ABC' AS locus,
        FALSE AS theoretical
    FROM
        `epitopefinder-458404`.epitopes.raw_ABC;

    INSERT INTO `epitopefinder-458404`.epitopes.HLA_data (
        epitope_id,
        epitope_name,
        description,
        alleles, 
        required_alleles,
        locus,
        theoretical
    )
    SELECT
        ID AS epitope_id,
        Name AS epitope_name,
        Description AS description,
        Alleles,
        `Required Alleles`,
        'DQ' AS locus,
        FALSE AS theoretical
    FROM
        `epitopefinder-458404`.epitopes.raw_DQ;

    INSERT INTO `epitopefinder-458404`.epitopes.HLA_data (
        epitope_id,
        epitope_name,
        description,
        alleles, 
        required_alleles,
        locus,
        theoretical
    )
    SELECT
        ID AS epitope_id,
        Name AS epitope_name,
        Description AS description,
        Alleles,
        `Required Alleles`,
        'DRB' AS locus,
        FALSE AS theoretical
    FROM
        `epitopefinder-458404`.epitopes.raw_DRB;

    INSERT INTO `epitopefinder-458404`.epitopes.HLA_data (
        epitope_id,
        epitope_name,
        description,
        alleles, 
        required_alleles,
        locus,
        theoretical
    )
    SELECT
        ID AS epitope_id,
        Name AS epitope_name,
        Description AS description,
        Alleles,
        `Required Alleles`,
        'MICA' AS locus,
        FALSE AS theoretical
    FROM
        `epitopefinder-458404`.epitopes.raw_MICA;

    INSERT INTO `epitopefinder-458404`.epitopes.HLA_data (
        epitope_id,
        epitope_name,
        description,
        alleles, 
        required_alleles,
        locus,
        theoretical
    )
    SELECT
        ID AS epitope_id,
        Name AS epitope_name,
        Description AS description,
        Alleles,
        `Required Alleles`,
        'DP' AS locus,
        FALSE AS theoretical
    FROM
        `epitopefinder-458404`.epitopes.raw_DP;

    INSERT INTO `epitopefinder-458404`.epitopes.HLA_data (
        epitope_id,
        epitope_name,
        description,
        alleles, 
        required_alleles,
        locus,
        theoretical
    )
    SELECT
        ID AS epitope_id,
        Name AS epitope_name,
        Description AS description,
        Alleles,
        `Required Alleles`,
        'DRDQDP' AS locus,
        FALSE AS theoretical
    FROM
        `epitopefinder-458404`.epitopes.raw_DRDQDP;

    INSERT INTO `epitopefinder-458404`.epitopes.HLA_data (
        epitope_id,
        epitope_name,
        description,
        alleles, 
        required_alleles,
        locus,
        theoretical
    )
    SELECT
        epitope_id,
        epitope_name,
        description,
        alleles,
        required_alleles,
        locus,
        theoretical
    FROM
        `epitopefinder-458404`.epitopes.raw_theoretical;
