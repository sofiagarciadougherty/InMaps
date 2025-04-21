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
from collections import deque


app = FastAPI()

CSV_PATH = "booth_coordinates.csv"

# Add calibration constants
CELL_SIZE = 40  # pixels per grid cell
# Default conversion factor - calibratable
METERS_TO_GRID_FACTOR = 1.0  # 1 grid = 1 meter

def load_booth_data(csv_path):
    df = pd.read_csv(csv_path, encoding_errors='replace',on_bad_lines="skip")
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
        elif "zone" in type.lower():
            booth_type = "Zone"
        elif "stairs" in type.lower():
             booth_type = "stairs"
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

def generate_venue_grid(csv_path, grid_size=CELL_SIZE):
    df = pd.read_csv(csv_path, encoding_errors='replace')
    parsed = []
    for cell in df["Coordinates"]:
        if not isinstance(cell, str): continue
        coord_str = re.sub(r'([{,]\s*)(\w+)\s*:', r'\1"\2":', cell)
        try:
            coords = json.loads(coord_str)
            parsed.append(coords)
        except json.JSONDecodeError:
            continue

    max_x = max(c["end"]["x"] for c in parsed)
    max_y = max(c["end"]["y"] for c in parsed)
    width  = (max_x + grid_size) // grid_size
    height = (max_y + grid_size) // grid_size
    grid = np.ones((height, width), dtype=int)

    for coords in parsed:
        sx, sy = coords["start"]["x"], coords["start"]["y"]
        ex, ey = coords["end"]["x"],   coords["end"]["y"]
        for gx in range(sx//grid_size, ex//grid_size + 1):
            for gy in range(sy//grid_size, ey//grid_size + 1):
                if 0 <= gx < width and 0 <= gy < height:
                    grid[gy][gx] = 0
    return grid.tolist()




booth_data = load_booth_data(CSV_PATH)
VENUE_GRID = generate_venue_grid(CSV_PATH)
WALKABLE_ZONES = []

for booth in booth_data:
    if booth["type"].lower() == "zone" and booth["name"].strip().lower() == "walkable":
        start = (int(booth["area"]["start"]["x"] // CELL_SIZE), int(booth["area"]["start"]["y"] // CELL_SIZE))
        end   = (int(booth["area"]["end"]["x"]   // CELL_SIZE), int(booth["area"]["end"]["y"]   // CELL_SIZE))
        WALKABLE_ZONES.append({
            "start": start,
            "end": end
        })

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
NAME_TO_ID = {
    "Beacon 1":  "14b00739",
    "Beacon 2":  "14b6072G",
    "Beacon 3":  "14b7072H",
    "Beacon 4":  "14bC072N",
    "Beacon 5":  "14bE072Q",
    "Beacon 6":  "14bF072R",
    "Beacon 7":  "14bK072V",
    "Beacon 8":  "14bM072X",
    "Beacon 9":  "14j006gQ",
    "Beacon 10": "14j606Gv",
    "Beacon 11": "14j706Gw",
    "Beacon 12": "14j706gX",
    "Beacon 13": "14j906Gy",
    "Beacon 14": "14jd06i0",
    "Beacon 15": "14jj06i6",
    "Beacon 16": "14jr06gF",
    "Beacon 17": "14jr08Ef",
    "Beacon 18": "14js06gG",
    "Beacon 19": "14jv06gK",
    "Beacon 20": "14jw08Ek",
}

# Create reverse mapping (MAC to ID)
MAC_TO_ID_MAP = {mac: id for id, mac in BEACON_MAC_MAP.items()}

# Beacon positions (using iOS IDs for consistency with frontend)
BEACON_POSITIONS = {}
for b in booth_data:
    if b["type"] != "beacon":
        continue
    ascii_id = NAME_TO_ID.get(b["name"])
    if not ascii_id:
        continue
    BEACON_POSITIONS[ascii_id] = (
        int(b["center"]["x"] // CELL_SIZE),
        int(b["center"]["y"] // CELL_SIZE),
    )



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

    goal_x = int(booth["center"]["x"] // CELL_SIZE)
    goal_y = int(booth["center"]["y"] // CELL_SIZE)
    n_rows, n_cols = len(VENUE_GRID), len(VENUE_GRID[0])
    goal_x = max(0, min(goal_x, n_cols - 1))
    goal_y = max(0, min(goal_y, n_rows - 1))
    goal_grid = (goal_x, goal_y)

    def find_nearest_free_cell(goal, grid):
        h, w = len(grid), len(grid[0])
        q = deque([(goal[0], goal[1])])
        seen = { (goal[0], goal[1]) }
        while q:
            x, y = q.popleft()
            if grid[y][x] == 1:
                return (x, y)
            for dx, dy in ((0,1),(1,0),(-1,0),(0,-1)):
                nx, ny = x+dx, y+dy
                if 0 <= nx < w and 0 <= ny < h and (nx,ny) not in seen:
                    seen.add((nx,ny))
                    q.append((nx,ny))
        return None

    print(f"📍 Routing from {request.from_} to grid cell {goal_grid}")
    print("🧱 Sample grid slice at goal:")
    print(np.array(VENUE_GRID)[goal_grid[1]-1:goal_grid[1]+2, goal_grid[0]-1:goal_grid[0]+2])

    # 🔁 If goal is blocked, find a nearby free cell
    if VENUE_GRID[goal_grid[1]][goal_grid[0]] == 0:
        print("⚠️ Goal is blocked. Searching for nearby free cell...")
        new_goal = find_nearest_free_cell(goal_grid, VENUE_GRID)
        if not new_goal:
            print("❌ No valid nearby goal found (even after search).")
            return JSONResponse(
                content={"error": "User likely on the wrong floor. Please go to the 2nd floor."},
                status_code=404
            )
        print(f"✅ Redirected goal to: {new_goal}")
        goal_grid = new_goal

    path = a_star(tuple(request.from_), goal_grid)

    if not path:
        print("❌ A* search failed: no path found even after redirecting goal.")
        return JSONResponse(
            content={"error": "User likely on the wrong floor. Please go to the 2nd floor."},
            status_code=404
        )

    print(f"🧭 Final path: {path}")
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
    global WALKABLE_ZONES
    visual_elements = []
    WALKABLE_ZONES.clear()  # Clear old walkable zones first

    for booth in booth_data:
        element = {
            "name": booth["name"],
            "description": booth["description"],
            "type": booth["type"],
            "start": booth["area"]["start"],
            "end": booth["area"]["end"]
        }
        visual_elements.append(element)

        # ⚡️ If the booth is a walkable zone, add it
        if booth["type"].lower() == "zone" and booth["name"].strip().lower() == "walkable":
            start_x = int(booth["area"]["start"]["x"] // CELL_SIZE)
            start_y = int(booth["area"]["start"]["y"] // CELL_SIZE)
            end_x   = int(booth["area"]["end"]["x"]   // CELL_SIZE)
            end_y   = int(booth["area"]["end"]["y"]   // CELL_SIZE)
            WALKABLE_ZONES.append({
                "start": (start_x, start_y),
                "end":   (end_x, end_y)
            })

    print(f"✅ Loaded {len(WALKABLE_ZONES)} walkable zones.")
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
    grid_distance = math.sqrt(dx*2 + dy*2)

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
def is_inside_walkable(x, y, walkable_zones):
    for area in walkable_zones:
        sx, sy = area["start"]
        ex, ey = area["end"]
        min_x = min(sx, ex)
        max_x = max(sx, ex)
        min_y = min(sy, ey)
        max_y = max(sy, ey)

        if min_x <= x <= max_x and min_y <= y <= max_y:
            return True
    return False


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
                    if is_inside_walkable(nx, ny, WALKABLE_ZONES) and (nx, ny) not in visited:
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