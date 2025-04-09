export interface GridCoord {
  row: number;
  col: number;
}

// 8-direction A* pathfinding with octile heuristic
export function findPath(start: GridCoord, end: GridCoord, grid: number[][]) {
  const numRows = grid.length;
  const numCols = grid[0].length;
  const directions = [
    [-1, 0], [1, 0], [0, -1], [0, 1],
    [-1, -1], [-1, 1], [1, -1], [1, 1],
  ];

  function moveCost(dr: number, dc: number) {
    return (dr !== 0 && dc !== 0) ? Math.SQRT2 : 1;
  }

  function isWalkable(r: number, c: number) {
    return r >= 0 && r < numRows && c >= 0 && c < numCols && grid[r][c] === 1;
  }

  function heuristic(r1: number, c1: number, r2: number, c2: number) {
    const dr = Math.abs(r1 - r2);
    const dc = Math.abs(c1 - c2);
    return dr + dc + (Math.SQRT2 - 2) * Math.min(dr, dc);
  }

  const openList = [];
  const cameFrom: Record<string, GridCoord> = {};
  const gScore = Array.from({ length: numRows }, () => Array(numCols).fill(Infinity));

  gScore[start.row][start.col] = 0;
  openList.push({ row: start.row, col: start.col, f: heuristic(start.row, start.col, end.row, end.col) });

  while (openList.length > 0) {
    openList.sort((a, b) => a.f - b.f);
    const current = openList.shift();
    if (!current) break;

    const { row, col } = current;
    if (row === end.row && col === end.col) return reconstructPath(cameFrom, end);

    for (const [dr, dc] of directions) {
      const nr = row + dr;
      const nc = col + dc;
      if (!isWalkable(nr, nc)) continue;

      const tentativeG = gScore[row][col] + moveCost(dr, dc);
      if (tentativeG < gScore[nr][nc]) {
        cameFrom[`${nr},${nc}`] = { row, col };
        gScore[nr][nc] = tentativeG;
        const fVal = tentativeG + heuristic(nr, nc, end.row, end.col);
        const existing = openList.find(n => n.row === nr && n.col === nc);
        if (existing) {
          existing.f = fVal;
        } else {
          openList.push({ row: nr, col: nc, f: fVal });
        }
      }
    }
  }

  return [];

  function reconstructPath(came: Record<string, GridCoord>, goal: GridCoord) {
    const path = [];
    let curr = goal;
    while (came[`${curr.row},${curr.col}`]) {
      path.push({ x: curr.col, y: curr.row });
      curr = came[`${curr.row},${curr.col}`];
    }
    path.push({ x: curr.col, y: curr.row });
    return path.reverse();
  }
}
