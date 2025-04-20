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
from fastapi.staticfiles import StaticFiles
import os

app = FastAPI()

# Serve static files from the "background" folder at /background
background_dir = os.path.join(os.path.dirname(__file__), "background")
app.mount("/background", StaticFiles(directory=background_dir), name="background")

# Load config file for scale and conversion factors
CONFIG_PATH = os.path.join(os.path.dirname(__file__), "config", "config.json")
with open(CONFIG_PATH, "r") as f:
    config = json.load(f)

# Use scale["primary"] for meters-per-pixel conversion
METERS_PER_PIXEL = config["scale"]["primary"]  # meters per pixel
# Set cell size so 1 grid cell = 1 meter (pixels per cell)
CELL_SIZE = 1.0 / METERS_PER_PIXEL

# Always set meters-to-grid-factor to 1.0 (1 grid = 1 meter)
METERS_TO_GRID_FACTOR = 1.0

POI_CSV_PATH = os.path.join(os.path.dirname(__file__), "poi_coordinates.csv")
CSV_PATH = POI_CSV_PATH  # Remove booth_coordinates.csv dependency

def load_booth_data(csv_path):
    df = pd.read_csv(csv_path)
    booths = []
    print("📦 Loading booths from CSV...")

    for _, row in df.iterrows():
        coord_cell = row["Coordinates"]
        if not isinstance(coord_cell, str):
            print("⚠️ Skipping row — Coordinates is not a string:", coord_cell)
            continue
        try:
            coords = json.loads(coord_cell.replace('\"', '"'))
            center = ast.literal_eval(row["Center Coordinates"])
        except Exception as e:
            print(f"⚠️ Skipping row — JSON parsing failed: {e}")
            continue

        if "blocker" in row["Name"].lower():
            booth_type = "blocker"
        elif "booth" in row["Name"].lower():
            booth_type = "booth"
        else:
            booth_type = "other"  # default/fallback for stuff like bathroom

        name = row["Name"].strip()

        print(f"✅ Loaded booth: {name} ({booth_type})")

        booths.append({
            "booth_id": int(row["Booth ID"]),
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

def load_poi_and_beacon_data(csv_path):
    df = pd.read_csv(csv_path)
    booths = []
    beacons = {}
    print("📦 Loading POIs and beacons from CSV...")

    for _, row in df.iterrows():
        name = str(row.get("Name", "")).strip()
        # Use Start_X (px) and Start_Y (px) for position in pixels
        start_x = row.get("Start_X (px)")
        start_y = row.get("Start_Y (px)")
        end_x = row.get("End_X (px)")
        end_y = row.get("End_Y (px)")
        center_px = row.get("Center (px)")
        # Parse center if available
        try:
            if isinstance(center_px, str) and center_px.startswith("("):
                center = ast.literal_eval(center_px)
            else:
                center = (start_x, start_y)
        except Exception:
            center = (start_x, start_y)

        if name.lower().startswith("beacon"):
            # Treat as beacon
            if pd.notnull(start_x) and pd.notnull(start_y):
                beacons[name] = (int(start_x), int(start_y))
                print(f"✅ Loaded beacon: {name} at ({start_x}, {start_y})")
            continue

        # Otherwise, treat as booth
        booth_type = "booth"
        print(f"✅ Loaded booth: {name} ({booth_type})")
        booths.append({
            "name": name,
            "type": booth_type,
            "area": {
                "start": {"x": int(start_x) if pd.notnull(start_x) else 0, "y": int(start_y) if pd.notnull(start_y) else 0},
                "end": {"x": int(end_x) if pd.notnull(end_x) else 0, "y": int(end_y) if pd.notnull(end_y) else 0},
            },
            "center": {"x": int(center[0]) if center else 0, "y": int(center[1]) if center else 0}
        })
    print(f"📊 Total booths loaded: {len(booths)}")
    print(f"📡 Total beacons loaded: {len(beacons)}")
    return booths, beacons

def generate_venue_grid(csv_path, canvas_width=800, canvas_height=600, grid_size=None):
    # Always use CELL_SIZE so 1 grid cell = 1 meter
    grid_size = CELL_SIZE
    df = pd.read_csv(csv_path)
    grid_width = int(canvas_width // grid_size)
    grid_height = int(canvas_height // grid_size)
    venue_grid = np.ones((grid_height, grid_width), dtype=int)

    for _, row in df.iterrows():
        name = str(row.get("Name", "")).strip()
        # Only treat as booth/obstacle if not a beacon
        if name.lower().startswith("beacon"):
            continue
        # Use Start/End coordinates
        start_x = row.get("Start_X (px)")
        start_y = row.get("Start_Y (px)")
        end_x = row.get("End_X (px)")
        end_y = row.get("End_Y (px)")
        if pd.isnull(start_x) or pd.isnull(start_y) or pd.isnull(end_x) or pd.isnull(end_y):
            continue
        start_px_x = int(start_x)
        start_px_y = int(start_y)
        end_px_x = int(end_x)
        end_px_y = int(end_y)
        for px_x in range(start_px_x, end_px_x + 1):
            for px_y in range(start_px_y, end_px_y + 1):
                gx = px_x // grid_size
                gy = px_y // grid_size
                if 0 <= gx < grid_width and 0 <= gy < grid_height:
                    venue_grid[gy][gx] = 0
    return venue_grid.tolist()

booth_data, BEACON_POSITIONS = load_poi_and_beacon_data(POI_CSV_PATH)
VENUE_GRID = generate_venue_grid(POI_CSV_PATH)

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

    # Use CELL_SIZE for grid conversion (1 cell = 1 meter)
    cell_size = CELL_SIZE
    goal_grid = (
        int(booth["center"]["x"] // cell_size),
        int(booth["center"]["y"] // cell_size)
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
    # Always reload from poi_coordinates.csv to ensure up-to-date data
    df = pd.read_csv(POI_CSV_PATH)
    booths = []
    for _, row in df.iterrows():
        name = str(row.get("Name", "")).strip()
        # If the name does NOT start with 'beacon' (case-insensitive), treat as booth
        if not name.lower().startswith("beacon"):
            start_x = row.get("Start_X (px)")
            start_y = row.get("Start_Y (px)")
            end_x = row.get("End_X (px)")
            end_y = row.get("End_Y (px)")
            center_px = row.get("Center (px)")
            try:
                if isinstance(center_px, str) and center_px.startswith("("):
                    center = ast.literal_eval(center_px)
                else:
                    center = (start_x, start_y)
            except Exception:
                center = (start_x, start_y)
            booths.append({
                "name": name,
                "type": "booth",
                "area": {
                    "start": {"x": int(start_x) if pd.notnull(start_x) else 0, "y": int(start_y) if pd.notnull(start_y) else 0},
                    "end": {"x": int(end_x) if pd.notnull(end_x) else 0, "y": int(end_y) if pd.notnull(end_y) else 0},
                },
                "center": {"x": int(center[0]) if center else 0, "y": int(center[1]) if center else 0}
            })
    return booths

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
        "gridCellSize": CELL_SIZE,  # pixels per grid cell (1 cell = 1 meter)
        "metersToGridFactor": METERS_TO_GRID_FACTOR,  # always 1.0 now
        "metersPerPixel": METERS_PER_PIXEL,  # meters per pixel
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