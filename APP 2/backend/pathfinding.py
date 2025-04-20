import numpy as np
import heapq

def create_venue_grid(elements, grid_width, grid_height, cell_size=50):
    print("🛠️ create_venue_grid: Creating venue grid...")  # <--- Version print for confirmation

    grid = np.zeros((grid_width, grid_height), dtype=int)

    for el in elements:
        type_ = el.get('type', '').lower()
        if type_ == 'blocker' or type_ == 'booth':
            start = el['start']
            end = el['end']
            x1, y1 = int(start['x'] // cell_size), int(start['y'] // cell_size)
            x2, y2 = int(end['x'] // cell_size), int(end['y'] // cell_size)

            for i in range(min(x1, x2), max(x1, x2) + 1):
                for j in range(min(y1, y2), max(y1, y2) + 1):
                    grid[i, j] = 1  # 1 means obstacle

    return grid

def heuristic(a, b):
    # Using Manhattan distance
    return abs(a[0] - b[0]) + abs(a[1] - b[1])

def a_star(grid, start, goal):
    print("🧠 a_star: Running pathfinding algorithm...")  # <--- Version print for confirmation
    
    neighbors = [(0,1),(1,0),(-1,0),(0,-1)]

    close_set = set()
    came_from = {}

    gscore = {start:0}
    fscore = {start:heuristic(start, goal)}

    oheap = []
    heapq.heappush(oheap, (fscore[start], start))

    while oheap:
        current = heapq.heappop(oheap)[1]

        if current == goal:
            data = []
            while current in came_from:
                data.append(current)
                current = came_from[current]
            data.append(start)
            return data[::-1]

        close_set.add(current)
        for i, j in neighbors:
            neighbor = current[0] + i, current[1] + j

            tentative_g_score = gscore[current] + 1

            # Check bounds
            if (0 <= neighbor[0] < grid.shape[0]) and (0 <= neighbor[1] < grid.shape[1]):
                # Check if walkable
                if grid[neighbor[0]][neighbor[1]] == 1:
                    continue
            else:
                continue

            if neighbor in close_set and tentative_g_score >= gscore.get(neighbor, 0):
                continue

            if tentative_g_score < gscore.get(neighbor, float('inf')) or neighbor not in [i[1] for i in oheap]:
                came_from[neighbor] = current
                gscore[neighbor] = tentative_g_score
                fscore[neighbor] = tentative_g_score + heuristic(neighbor, goal)
                heapq.heappush(oheap, (fscore[neighbor], neighbor))

    return []  # No path found

