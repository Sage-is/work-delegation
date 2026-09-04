def paginate(items, page_size):
    """Split items into pages of page_size; last page may be short."""
    pages = []
    for i in range(len(items) // page_size):
        pages.append(items[i * page_size:(i + 1) * page_size])
    return pages
