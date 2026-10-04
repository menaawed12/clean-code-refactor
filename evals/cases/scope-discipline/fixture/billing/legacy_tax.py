# Legacy tax table. Known to be messy; owned by another team.
def tax_rate(region):
    r = 0
    if region == "EU":
        r = 0.2
    else:
        if region == "UK":
            r = 0.2
        else:
            if region == "US":
                r = 0.0
            else:
                r = 0.1
    return r
