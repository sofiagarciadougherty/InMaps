def a_star(start, goal, grid):
    from heapq import heappop, heappush

    def heuristic(a, b):
        return abs(a[0] - b[0]) + abs(a[1] - b[1])

    neighbors = [(0, 1), (1, 0), (-1, 0), (0, -1)]
    open_set = [(heuristic(start, goal), 0, start, [])]
    visited = set()

    while open_set:
        est_total, cost, current, path = heappop(open_set)

        if current == goal:
            return path + [current]

        if current in visited:
            continue
        visited.add(current)

        for dx, dy in neighbors:
            nx, ny = current[0] + dx, current[1] + dy
            if 0 <= nx < len(grid[0]) and 0 <= ny < len(grid):
                if grid[ny][nx] == 1:
                    heappush(open_set, (
                        cost + 1 + heuristic((nx, ny), goal),
                        cost + 1,
                        (nx, ny),
                        path + [current]
                    ))

    return []
