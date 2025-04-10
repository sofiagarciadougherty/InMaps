from fastapi import FastAPI
from pydantic import BaseModel
from typing import List, Dict
import math

app = FastAPI()

# ======= MOCK BEACON & BOOTH DATA =======

# (x, y) positions of each beacon by UUID
BEACON_POSITIONS = {
    "D1:AA:BE:01:01:01": (2, 2),
    "D2:BB:BE:02:02:02": (6, 2),
    "D3:CC:BE:03:03:03": (4, 6)
}

# Booths at specific grid coordinates
BOOTH_LOCATIONS = {
    "Tesla": (1, 8),
    "Walmart": (7, 1),
    "Apple": (6, 6)
}

# Grid layout where 1 is walkable path, 0 is wall
VENUE_GRID = [
    [1, 1, 1, 1, 1, 1, 1, 1],
    [1, 0, 0, 0, 1, 0, 0, 1],
    [1, 1, 1, 0, 1, 1, 1, 1],
    [0, 0, 1, 0, 0, 0, 0, 1],
    [1, 1, 1, 1, 1, 1, 0, 1],
    [1, 0, 0, 0, 0, 1, 0, 1],
    [1, 1, 1, 1, 0, 1, 1, 1],
    [0, 0, 0, 1, 1, 1, 0, 0],
]

# ======= REQUEST MODELS =======

class BLEReading(BaseModel):
    uuid: str
    rssi: int

class BLEScan(BaseModel):
    ble_data: List[BLEReading]

class PathRequest(BaseModel):
    from_: List[int]
    to: str

# ======= API ENDPOINTS =======

@app.post("/locate")
def locate_user(data: BLEScan):
    weighted_sum_x = 0
    weighted_sum_y = 0
    total_weight = 0

    for reading in data.ble_data:
        pos = BEACON_POSITIONS.get(reading.uuid)
        if pos:
            weight = 1 / (abs(reading.rssi) + 1)
            weighted_sum_x += pos[0] * weight
            weighted_sum_y += pos[1] * weight
            total_weight += weight

    if total_weight == 0:
        return {"x": -1, "y": -1}

    x = round(weighted_sum_x / total_weight)
    y = round(weighted_sum_y / total_weight)

    return {"x": x, "y": y}

@app.post("/path")
def get_path(req: PathRequest):
    start = tuple(req.from_)
    end = BOOTH_LOCATIONS.get(req.to)
    if not end:
        return {"error": "Booth not found"}

    path = a_star(start, end)
    return {"path": path}

# ======= A* PATHFINDING =======

def a_star(start, goal):
    from heapq import heappop, heappush

    def heuristic(a, b):
        return abs(a[0]-b[0]) + abs(a[1]-b[1])

    neighbors = [(0,1),(1,0),(-1,0),(0,-1)]
    open_set = [(0 + heuristic(start, goal), 0, start, [])]
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
            if 0 <= nx < len(VENUE_GRID[0]) and 0 <= ny < len(VENUE_GRID):
                if VENUE_GRID[ny][nx] == 1:
                    heappush(open_set, (
                        cost + 1 + heuristic((nx, ny), goal),
                        cost + 1,
                        (nx, ny),
                        path + [current]
                    ))

    return []
