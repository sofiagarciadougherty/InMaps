from fastapi import FastAPI
from pydantic import BaseModel
from typing import List, Dict
from fastapi.responses import JSONResponse
from heapq import heappop, heappush
import pandas as pd
import numpy as np
import json
import ast
import math
import re

app = FastAPI()

CSV_PATH = "booth_coordinates.csv"

# Add calibration constants
CELL_SIZE = 40  # pixels per grid cell
# Default conversion factor - calibratable
METERS_TO_GRID_FACTOR = 1.0  # 1 grid = 1 meter

def load_booth_data(csv_path):
    df = pd.read_csv(csv_path)
    booths = []
    print("📦 Loading booths from CSV...")

    for _, row in df.iterrows():
        coord_cell = row["Coordinates"]
        if not isinstance(coord_cell, str):
            print("⚠️ Skipping row — Coordinates is not a string:", coord_cell)
            continue

        # 1) Quote unquoted keys so it's valid JSON
        try:
            coord_str = re.sub(
                r'([{,]\s*)(\w+)\s*:',
                r'\1"\2":',
                coord_cell
            )
            coords = json.loads(coord_str)
            center = ast.literal_eval(row["Center Coordinates"])
        except Exception as e:
            print(f"⚠️ Skipping row — JSON parsing failed: {e}")
            continue

        # 2) Determine type
        type = row["Type"].strip()
        if "beacon" in type.lower():
            booth_type = "beacon"
        elif "booth" in type.lower():
            booth_type = "booth"
        else:
            booth_type = "other"
            
        # Get the name from the row
        name = str(row["Name"]).strip()

        # 3) Pull out description
        description = str(row["Description"]).strip()

        print(f"✅ Loaded booth: {name} ({booth_type})")

        booths.append({
            "booth_id": int(row["ID"]),         # was row["Booth ID"]
            "name": name,
            "description": description,         # now defined
            "type": booth_type,
            "area": {
                "start": {"x": coords["start"]["x"], "y": coords["start"]["y"]},
                "end":   {"x": coords["end"]["x"],   "y": coords["end"]["y"]},
            },
            "center": {"x": center[0], "y": center[1]}
        })

    print(f"📊 Total booths loaded: {len(booths)}")
    return booths

def generate_venue_grid(csv_path, canvas_width=800, canvas_height=600, grid_size=CELL_SIZE):
    df = pd.read_csv(csv_path)
    grid_width = canvas_width // grid_size
    grid_height = canvas_height // grid_size
    venue_grid = np.ones((grid_height, grid_width), dtype=int)

    for _, row in df.iterrows():
        coord_cell = row["Coordinates"]
        if not isinstance(coord_cell, str):
            continue
        try:
            coord_str = re.sub(r'([{,]\s*)(\w+)\s*:', r'\1"\2":', coord_cell)
            coords    = json.loads(coord_str)
        except Exception:
            continue

        if any(t in row["Name"].lower() for t in ["blocker", "booth", "bathroom", "other"]):
            start_px_x = int(coords["start"]["x"])
            start_px_y = int(coords["start"]["y"])
            end_px_x = int(coords["end"]["x"])
            end_px_y = int(coords["end"]["y"])

            # Compute the grid cells covered by the booth/blocker area
            start_grid_x = start_px_x // grid_size
            start_grid_y = start_px_y // grid_size
            end_grid_x = end_px_x // grid_size
            end_grid_y = end_px_y // grid_size

            for gx in range(start_grid_x, end_grid_x + 1):
                for gy in range(start_grid_y, end_grid_y + 1):
                    if 0 <= gx < grid_width and 0 <= gy < grid_height:
                        venue_grid[gy][gx] = 0  # Mark grid cell as obstacle (blocked)

    return venue_grid.tolist()




booth_data = load_booth_data(CSV_PATH)
VENUE_GRID = generate_venue_grid(CSV_PATH)

# Mapping between iOS beacon IDs and Android MAC addresses
BEACON_MAC_MAP = {
    "14b00739": "00:FA:B6:2F:50:8C",
    "14b6072G": "00:FA:B6:2F:51:28",
    "14b7072H": "00:FA:B6:2F:51:25",
    "14bC072N": "00:FA:B6:2F:51:16",
    "14bE072Q": "00:FA:B6:2F:51:10",
    "14bF072R": "00:FA:B6:2F:51:0D",
    "14bK072V": "00:FA:B6:2F:51:01",
    "14bM072X": "00:FA:B6:2F:50:FB",
    "14j006gQ": "00:FA:B6:31:02:BA",
    "14j606Gv": "00:FA:B6:31:12:F8",
    "14j706Gw": "00:FA:B6:31:12:F5",
    "14j706gX": "00:FA:B6:31:02:A5",
    "14j906Gy": "00:FA:B6:31:12:EF",
    "14jd06i0": "00:FA:B6:31:01:A0",
    "14jj06i6": "00:FA:B6:31:01:8E",
    "14jr06gF": "00:FA:B6:31:02:D5",
    "14jr08Ef": "00:FA:B6:30:C2:F1",
    "14js06gG": "00:FA:B6:31:02:D2",
    "14jv06gK": "00:FA:B6:31:02:C9",
    "14jw08Ek": "00:FA:B6:30:C2:E2"
}

# Create reverse mapping (MAC to ID)
MAC_TO_ID_MAP = {mac: id for id, mac in BEACON_MAC_MAP.items()}

# Beacon positions (using iOS IDs for consistency with frontend)
# BEACON_POSITIONS = {
#     "14j906Gy": (0, 0),
#     "14jr08Ef": (1, 0),
#     "14j606Gv": (0, 1)
# }

# ====== Models ======
class BLEReading(BaseModel):
    uuid: str
    rssi: int

class BLEScan(BaseModel):
    ble_data: List[BLEReading]

class PathRequest(BaseModel):
    from_: List[int]
    to: str

class CalibrationRequest(BaseModel):
    beacon1_id: str
    beacon2_id: str
    known_distance_meters: float

# Function to convert RSSI to physical distance in meters
def rssi_to_distance(rssi: int, tx_power: int = -59, path_loss_exponent: float = 2.0) -> float:
    """
    Convert RSSI value to physical distance in meters

    Args:
        rssi: The RSSI value (in dBm)
        tx_power: Calibrated signal strength at 1 meter (default: -59 dBm)
        path_loss_exponent: Environment-specific attenuation factor (default: 2.0 for free space)

    Returns:
        Estimated distance in meters
    """
    return math.pow(10, (tx_power - rssi) / (10 * path_loss_exponent))

# ====== API ======
@app.post("/locate")
def locate_user(data: BLEScan):
    weighted_sum_x = 0
    weighted_sum_y = 0
    total_weight = 0

    for reading in data.ble_data:
        # Check if the UUID is a MAC address and map it if necessary
        beacon_id = reading.uuid
        if ":" in reading.uuid:  # This is likely a MAC address
            beacon_id = MAC_TO_ID_MAP.get(reading.uuid, reading.uuid)

        pos = BEACON_POSITIONS.get(beacon_id)
        if pos:
            # Convert RSSI to distance in meters
            distance_meters = rssi_to_distance(reading.rssi)
            # Convert weight based on physical distance (inverse square law)
            weight = 1 / max(0.1, distance_meters ** 2)

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
    print("✅ /path endpoint hit:", request)
    booth_name = request.to.strip().lower()
    booth = next((b for b in booth_data if b["name"].strip().lower() == booth_name), None)

    if not booth:
        print("❌ Booth not found:", booth_name)
        return JSONResponse(content={"error": "Booth not found"}, status_code=404)

    cell_size = 50
    goal_grid = (
        int(booth["center"]["x"] // CELL_SIZE),
        int(booth["center"]["y"] // CELL_SIZE)
    )

    def find_nearest_free_cell(goal, grid):
        directions = [
            (0, 1), (1, 0), (-1, 0), (0, -1),
            (1, 1), (-1, -1), (1, -1), (-1, 1)
        ]
        for dx, dy in directions:
            nx, ny = goal[0] + dx, goal[1] + dy
            if 0 <= nx < len(grid[0]) and 0 <= ny < len(grid):
                if grid[ny][nx] == 1:
                    return (nx, ny)
        return None

    print(f"📍 Routing from {request.from_} to grid cell {goal_grid}")
    print("🧱 Sample grid slice at goal:")
    print(np.array(VENUE_GRID)[goal_grid[1]-1:goal_grid[1]+2, goal_grid[0]-1:goal_grid[0]+2])

    # 🔁 If goal is blocked, find a nearby free cell
    if VENUE_GRID[goal_grid[1]][goal_grid[0]] == 0:
        print("⚠️ Goal is blocked. Searching for nearby free cell...")
        new_goal = find_nearest_free_cell(goal_grid, VENUE_GRID)
        if not new_goal:
            print("❌ No valid nearby goal found.")
            return {"path": []}
        print(f"✅ Redirected goal to: {new_goal}")
        goal_grid = new_goal

    path = a_star(tuple(request.from_), goal_grid)
    print(f"🧭 Final path: {path}")
    if path:
        print(f"🏁 Last cell in path: {path[-1]}, Target goal: {goal_grid}")

    return {"path": path}


@app.get("/booths")
def get_all_booths():
    return booth_data

@app.get("/booths/{booth_id}")
def get_booth_by_id(booth_id: int):
    booth = next((b for b in booth_data if b["booth_id"] == booth_id), None)
    return booth or {"error": "Booth not found"}

@app.get("/map-data")
def get_map_data():
    visual_elements = []

    for booth in booth_data:
        visual_elements.append({
            "name": booth["name"],
            "description": booth["description"],
            "type": booth["type"],
            "start": booth["area"]["start"],
            "end": booth["area"]["end"]

        })

    return JSONResponse(content={"elements": visual_elements})

@app.get("/config")
def get_config():
    """Provide configuration data for the mobile app, including beacon positions and mapping."""
    return {
        "beaconPositions": {id: {"x": pos[0], "y": pos[1]} for id, pos in BEACON_POSITIONS.items()},
        "beaconIdMapping": BEACON_MAC_MAP,
        "gridCellSize": CELL_SIZE,  # pixels per grid cell
        "metersToGridFactor": METERS_TO_GRID_FACTOR,  # conversion factor for physical distance
        "txPower": -59  # Default reference RSSI at 1m
    }

@app.post("/calibrate")
def calibrate_system(data: CalibrationRequest):
    """
    Calibrate the system based on a known physical distance between two beacons
    
    This endpoint updates the METERS_TO_GRID_FACTOR based on the provided information
    """
    global METERS_TO_GRID_FACTOR
    
    # Get beacon positions
    beacon1_pos = BEACON_POSITIONS.get(data.beacon1_id)
    beacon2_pos = BEACON_POSITIONS.get(data.beacon2_id)
    
    if not beacon1_pos or not beacon2_pos:
        return JSONResponse(
            content={"error": "One or both beacon IDs not found"}, 
            status_code=400
        )
    
    # Calculate grid distance between beacons
    dx = beacon2_pos[0] - beacon1_pos[0]
    dy = beacon2_pos[1] - beacon1_pos[1]
    grid_distance = math.sqrt(dx**2 + dy**2)
    
    # Ensure we have a valid physical distance
    if data.known_distance_meters <= 0:
        return JSONResponse(
            content={"error": "Physical distance must be greater than zero"}, 
            status_code=400
        )
    
    # Calculate new meters-to-grid factor
    new_factor = grid_distance / data.known_distance_meters
    
    # Update the global factor
    METERS_TO_GRID_FACTOR = new_factor
    
    return {
        "success": True,
        "previousFactor": METERS_TO_GRID_FACTOR,
        "newFactor": new_factor,
        "gridDistance": grid_distance,
        "physicalDistance": data.known_distance_meters
    }

# ====== A* Algorithm ======
def a_star(start, goal):
    def heuristic(a, b):
        return abs(a[0] - b[0]) + abs(a[1] - b[1])

    neighbors = [(0, 1), (1, 0), (-1, 0), (0, -1)]
    open_set = [(heuristic(start, goal), 0, start, [])]
    visited = set()

    while open_set:
            est_total_cost, path_cost, current, path = heappop(open_set)

            if current == goal:
                return path + [current]

            if current in visited:
                continue
            visited.add(current)

            for dx, dy in neighbors:
                nx, ny = current[0] + dx, current[1] + dy

                # Check bounds
                if 0 <= nx < len(VENUE_GRID[0]) and 0 <= ny < len(VENUE_GRID):
                    # Check if the cell is walkable (1 = free space)
                    if VENUE_GRID[ny][nx] == 1 and (nx, ny) not in visited:
                        next_cost = path_cost + 1
                        estimated_total = next_cost + heuristic((nx, ny), goal)
                        heappush(open_set, (
                            estimated_total,
                            next_cost,
                            (nx, ny),
                            path + [current]
                        ))

    return []
    
@app.get("/")
def root():
    return {"message": "InMaps backend is running!"}