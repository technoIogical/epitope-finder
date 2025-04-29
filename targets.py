possible_targets = ["ABC", "DRB", "DQ", "DP", "MICA"]


def input_targets():
    print(
        "Possible targets include: 1. ABC 2. DRB 3. DQ 4. DP 5. MICA"
        "\n"
        "Type desired targets with spaces"
    )

    targets = input().split()
    for target in targets:
        if target not in possible_targets:
            raise Exception(
                f"{target} not found in possible_targets of {possible_targets}"
            )

    return targets
