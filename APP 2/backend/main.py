from fastapi import FastAPI
from pydantic import BaseModel
from typing import List, Dict
from heapq import heappop, heappush
import pandas as pd
import numpy as np
import json
import ast

app = FastAPI()

# ====== Load booth data and grid from uploaded CSV ======
CSV_PATH = "booth_coordinates.csv"

def load_booth_data(csv_path):
    df = pd.read_csv(csv_path)
    booths = []
    print("📦 Loading booths from CSV...")

    for _, row in df.iterrows():
        coord_cell = row["Coordinates (in pixels)"]
        if not isinstance(coord_cell, str):
            print("⚠️ Skipping row — Coordinates is not a string:", coord_cell)
            continue
        try:
            coords = json.loads(coord_cell)
            center = ast.literal_eval(row["Center"])
        except Exception as e:
            print(f"⚠️ Skipping row — JSON parsing failed: {e}")
            continue

        booth_type = "blocker" if "blocker" in row["Name"].lower() else "booth"
        name = row["Name"].strip()

        print(f"✅ Loaded booth: {name} ({booth_type})")

        booths.append({
            "booth_id": int(row["BOOTH ID"]),
            "name": name,
            "type": booth_type,
            "area": {
                "start": {"x": coords["start"]["x"], "y": coords["start"]["y"]},
                "end": {"x": coords["end"]["x"], "y": coords["end"]["y"]},
            },
            "center": {"x": center[0], "y": center[1]}
        })
    print(f"📊 Total booths loaded: {len(booths)}")
    return booths

def generate_venue_grid(csv_path, canvas_width=800, canvas_height=600, grid_size=20):
    df = pd.read_csv(csv_path)
    grid_width = canvas_width // grid_size
    grid_height = canvas_height // grid_size
    venue_grid = np.ones((grid_height, grid_width), dtype=int)

    for _, row in df.iterrows():
        coord_cell = row["Coordinates (in pixels)"]
        if not isinstance(coord_cell, str):
            continue
        try:
            coords = json.loads(coord_cell)
        except Exception:
            continue

        booth_type = "blocker" if "blocker" in row["Name"].lower() else "booth"

        start_x = int(coords["start"]["x"] // grid_size)
        start_y = int(coords["start"]["y"] // grid_size)
        end_x = int(coords["end"]["x"] // grid_size)
        end_y = int(coords["end"]["y"] // grid_size)

        start_x = max(0, min(start_x, grid_width - 1))
        end_x = max(0, min(end_x, grid_width - 1))
        start_y = max(0, min(start_y, grid_height - 1))
        end_y = max(0, min(end_y, grid_height - 1))

        if booth_type in ["booth", "blocker"]:
            venue_grid[start_y:end_y+1, start_x:end_x+1] = 0

    return venue_grid.tolist()

booth_data = load_booth_data(CSV_PATH)
VENUE_GRID = generate_venue_grid(CSV_PATH)

# ====== Beacon positions ======
BEACON_POSITIONS = {
    "D1:AA:BE:01:01:01": (2, 2),
    "D2:BB:BE:02:02:02": (6, 2),
    "D3:CC:BE:03:03:03": (4, 6)
}

# ====== Request Models ======
class BLEReading(BaseModel):
    uuid: str
    rssi: int

class BLEScan(BaseModel):
    ble_data: List[BLEReading]

class PathRequest(BaseModel):
    from_: List[int]
    to: str

class Point(BaseModel):
    x: float
    y: float

class Area(BaseModel):
    start: Point
    end: Point

class Booth(BaseModel):
    booth_id: int
    name: str
    type: str
    area: Area
    center: Point

# ====== API Endpoints ======
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
def get_path(request: PathRequest):
    print("📥 RAW path request:", request)    print("📥 request.to repr:", repr(request.to))
    print("🔎 Request to booth:", request.to)
    booth = next((b for b in booth_data if b["name"].strip().lower() == request.to.strip().lower()), None)
    if not booth:
        print("❌ Booth match failed — exact names:")
        for b in booth_data:
            print("-", repr(b["name"]))

    cell_size = 50

    goal = next((b for b in booth_data if b["name"].lower() == request.to.lower()), None)
    if not goal:
        print("❌ Booth not found")
        return {"path": []}

    # 🔁 Convert pixel to grid coordinates
    goal_grid = (int(goal["center"]["x"] // cell_size), int(goal["center"]["y"] // cell_size))
    print(f"🧭 Converting pixels {goal['center']} → grid {goal_grid}")

    path = a_star(tuple(request.from_), goal_grid, venue_grid)
    goal = booth["center"]
    print("📍 Routing to:", goal)
    return {"path": a_star(tuple(request.from_), (round(goal["x"]), round(goal["y"])))}

@app.get("/booths", response_model=List[Booth])
def get_all_booths():
    return booth_data

@app.get("/booths/{booth_id}", response_model=Booth)
def get_booth_by_id(booth_id: int):
    for booth in booth_data:
        if booth["booth_id"] == booth_id:
            return booth
    return {"error": "Booth not found"}

# ====== A* PATHFINDING ======
def a_star(start, goal):
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
            if 0 <= nx < len(VENUE_GRID[0]) and 0 <= ny < len(VENUE_GRID):
                if VENUE_GRID[ny][nx] == 1:
                    heappush(open_set, (
                        cost + 1 + heuristic((nx, ny), goal),
                        cost + 1,
                        (nx, ny),
                        path + [current]
                    ))

    return []

