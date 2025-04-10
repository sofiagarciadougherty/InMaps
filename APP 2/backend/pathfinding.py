import heapq

# Sample grid size and walls for testing
GRID_WIDTH = 10
GRID_HEIGHT = 10
WALLS = {(2, 2), (3, 2), (4, 2)}  # blocked cells

# Booth names mapped to their coordinates
BOOTH_COORDS = {
    "Tesla": (1, 7),
    "Apple": (5, 2),
    "Google": (2, 6),
    "Meta": (4, 8),
}


def heuristic(a, b):
    # Manhattan distance
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


def get_neighbors(node):
    x, y = node
    neighbors = [
        (x + 1, y),
        (x - 1, y),
        (x, y + 1),
        (x, y - 1)
    ]
    return [
        n for n in neighbors
        if 0 <= n[0] < GRID_WIDTH and 0 <= n[1] < GRID_HEIGHT and n not in WALLS
    ]


def a_star(start, goal):
    open_set = []
    heapq.heappush(open_set, (0, start))
    came_from = {}
    g_score = {start: 0}

    while open_set:
        _, current = heapq.heappop(open_set)

        if current == goal:
            path = []
            while current in came_from:
                path.append(current)
                current = came_from[current]
            path.append(start)
            path.reverse()
            return path

        for neighbor in get_neighbors(current):
            tentative_g = g_score[current] + 1
            if neighbor not in g_score or tentative_g < g_score[neighbor]:
                came_from[neighbor] = current
                g_score[neighbor] = tentative_g
                f_score = tentative_g + heuristic(neighbor, goal)
                heapq.heappush(open_set, (f_score, neighbor))

    return []  # no path found


def find_path(start, goal_name):
    if goal_name not in BOOTH_COORDS:
        return []

    goal = BOOTH_COORDS[goal_name]
    return a_star(tuple(start), goal)
