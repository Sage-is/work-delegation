def mean(values):
    return sum(values) / len(values)

def variance(values):
    m = mean(values)
    return sum((v - m) ** 2 for v in values) / len(values)

def zscore(value, values):
    import math
    return (value - mean(values)) / math.sqrt(variance(values))

def rolling(values, window):
    out = []
    for i in range(len(values) - window + 1):
        out.append(mean(values[i:i + window]))
    return out
