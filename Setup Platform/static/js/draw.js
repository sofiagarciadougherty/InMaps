// InMaps - Floorplan Evaluation Tool
// Drawing functionality for POIs and beacons

window.addEventListener('load', init);

let canvas, ctx;
let imageObj = new Image();
let gridOn = true;
let scaleX, scaleY;
let booths = []; // Array to store POI objects
let pois = []; // Array to store beacon objects
let currentPoints = []; // For "arbitrary" mode
let startPoint = null; // For "rectangle" mode
let elementCounter = 0; // Single counter for both POIs and beacons
let uniformDims = null; // for uniform mode (in pixels)
let imageLoaded = false;
let current_pos = { x: 0, y: 0 }; // Initialize current_pos
let isDrawingPOI = false; // Track if we're in beacon drawing mode
let mouseX, mouseY; // Added for onMouseMove
let currentElement = null; // Store the current element being drawn

// Use global variables from the template
let mode; // Will be initialized in init()

let uniformWidth = 1.0;  // Default uniform width in meters
let uniformHeight = 1.0; // Default uniform height in meters
let previousMode = 'rectangle';  // Keep track of previous mode

function init() {
    console.log("Initializing..."); // Debug log
    canvas = document.getElementById("drawingCanvas");
    ctx = canvas.getContext("2d");
    
    // Initialize mode from template
    mode = drawingMode;  // "arbitrary", "rectangle", or "uniform"
    console.log("Drawing mode:", mode); // Debug log

    // Set the title from the form
    document.getElementById("floorplanTitle").textContent = floorplanTitle;

    // Initialize mode selector
    const modeSelect = document.getElementById("drawingModeSelect");
    modeSelect.value = mode; // Set initial mode
    modeSelect.addEventListener('change', function(e) {
        const newMode = e.target.value;
        
        if (newMode === 'uniform') {
            // Show the uniform mode dialog
            const dialog = document.getElementById('uniformModeDialog');
            dialog.style.display = 'block';
            
            // Set current values in meters
            document.getElementById('uniformWidth').value = uniformWidth;
            document.getElementById('uniformHeight').value = uniformHeight;
            
            // Store the previous mode in case user cancels
            previousMode = currentDrawingMode;
            
            // Don't update the mode yet - wait for confirmation
            e.target.value = currentDrawingMode;
            return;
        }
        
        // For non-uniform modes, update directly
        updateDrawingMode(newMode);
    });

    // Initialize beacon button
    const poiButton = document.getElementById("togglePOI");
    console.log("Beacon button element:", poiButton); // Debug log
    if (poiButton) {
        console.log("Beacon button found, adding click handler"); // Debug log
        // Remove any existing click handlers
        poiButton.removeEventListener('click', togglePOIMode);
        // Add new click handler
        poiButton.addEventListener('click', togglePOIMode);
        // Test if the button is clickable
        poiButton.style.cursor = 'pointer';
    } else {
        console.error("Beacon button not found!"); // Debug log
    }

    imageObj.onload = function() {
        imageLoaded = true;
        
        // Calculate the maximum dimensions that fit in the container
        const containerWidth = canvas.parentElement.clientWidth;
        const maxWidth = containerWidth - 40; // 20px padding on each side
        
        // Calculate the scale to fit the image
        const scale = Math.min(maxWidth / imageObj.width, 1);
        
        // Set canvas dimensions
        canvas.width = imageObj.width * scale;
        canvas.height = imageObj.height * scale;
        
        // Compute scale factors (meters per pixel)
        scaleX = floorWidth / canvas.width;
        scaleY = floorHeight / canvas.height;
        
        // For uniform mode, convert booth dimensions from meters to pixels
        if (mode === "uniform") {
            uniformDims = {
                width: uniformWidth / scaleX,
                height: uniformHeight / scaleY
            };
        }
        
        drawCanvas();
    };
    imageObj.src = imageUrl;

    canvas.addEventListener('mousemove', onMouseMove);
    canvas.addEventListener('click', onCanvasClick);
    
    document.getElementById("finishBtn").addEventListener('click', finishDrawing);
    document.getElementById("clearBtn").addEventListener('click', clearDrawings);

    // Add event listener for Save button
    document.getElementById("saveButton").addEventListener("click", function() {
        // Update all input values in the tables and objects
        updateAllInputValues();
        // Update both CSV and tables
        generateCSV();
        updateBoothTable();
        updatePOITable();
        // Show save confirmation to user
        alert("All inputs have been saved successfully!");
    });

    // Add event listener for Report button
    document.getElementById("reportDownloadLink").addEventListener("click", async function(e) {
        e.preventDefault(); // Prevent default anchor behavior
        await generateReport();
    });
}

function togglePOIMode() {
    console.log("Toggle beacon mode function called"); // Debug log
    isDrawingPOI = !isDrawingPOI;
    console.log("New beacon mode state:", isDrawingPOI); // Debug log
    const poiButton = document.getElementById("togglePOI");
    if (poiButton) {
        console.log("Updating button text and class"); // Debug log
        poiButton.textContent = isDrawingPOI ? "Exit Beacon Mode" : "Add Beacons";
        poiButton.classList.toggle('active', isDrawingPOI);
        if (isDrawingPOI) {
            pois = []; // Clear existing beacons when entering beacon mode
            document.querySelector("#poiTable tbody").innerHTML = "";
            document.getElementById("poiCount").textContent = "Total Beacons: 0";
        }
        drawCanvas();
    }
}

function drawGrid() {
    const gridSize = 50; // pixels
    ctx.strokeStyle = "rgba(0, 0, 0, 0.1)";
    ctx.lineWidth = 1;
    
    // Draw vertical lines
    for (let x = 0; x <= canvas.width; x += gridSize) {
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, canvas.height);
        ctx.stroke();
    }
    
    // Draw horizontal lines
    for (let y = 0; y <= canvas.height; y += gridSize) {
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(canvas.width, y);
        ctx.stroke();
    }
}

function drawCanvas() {
    if (!ctx || !imageLoaded) return;
    
    // Clear canvas
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    
    // Draw image
    ctx.drawImage(imageObj, 0, 0, canvas.width, canvas.height);
    
    // Draw grid if enabled
    if (gridOn) {
        drawGrid();
    }
    
    // Draw all booths
    booths.forEach(booth => {
        if (booth.points) {
            // For arbitrary mode
            ctx.beginPath();
            ctx.moveTo(booth.points[0].x, booth.points[0].y);
            for (let i = 1; i < booth.points.length; i++) {
                ctx.lineTo(booth.points[i].x, booth.points[i].y);
            }
            ctx.closePath();
            ctx.strokeStyle = "red";
            ctx.lineWidth = 2;
            ctx.stroke();
            
            // Draw booth ID
            let centerX = booth.points.reduce((sum, p) => sum + p.x, 0) / booth.points.length;
            let centerY = booth.points.reduce((sum, p) => sum + p.y, 0) / booth.points.length;
            ctx.fillStyle = "red";
            ctx.font = "16px Arial";
            ctx.textAlign = "center";
            ctx.fillText(booth.id.toString(), centerX, centerY);
        } else {
            // For rectangle and uniform modes
            let startX = booth.start.x;
            let startY = booth.start.y;
            let width = booth.end.x - booth.start.x;
            let height = booth.end.y - booth.start.y;
            
            ctx.strokeStyle = "red";
            ctx.lineWidth = 2;
            ctx.strokeRect(startX, startY, width, height);
            
            // Draw booth ID
            let centerX = startX + width / 2;
            let centerY = startY + height / 2;
            ctx.fillStyle = "red";
            ctx.font = "16px Arial";
            ctx.textAlign = "center";
            ctx.fillText(booth.id.toString(), centerX, centerY);
        }
    });
    
    // Draw all beacons
    pois.forEach(poi => {
        // Draw beacon point
        ctx.beginPath();
        ctx.arc(poi.x, poi.y, 5, 0, 2 * Math.PI);
        ctx.fillStyle = "green";
        ctx.fill();
        
        // Draw beacon ID
        ctx.fillStyle = "green";
        ctx.font = "16px Arial";
        ctx.textAlign = "center";
        ctx.fillText(poi.id.toString(), poi.x, poi.y - 10);
    });
    
    // Draw current points for arbitrary mode
    if (currentPoints.length > 0) {
        ctx.beginPath();
        ctx.moveTo(currentPoints[0].x, currentPoints[0].y);
        for (let i = 1; i < currentPoints.length; i++) {
            ctx.lineTo(currentPoints[i].x, currentPoints[i].y);
        }
        ctx.strokeStyle = "red";
        ctx.lineWidth = 2;
        ctx.stroke();
    }
    
    // Draw current rectangle for rectangle mode
    if (startPoint) {
        let currentX = mouseX;
        let currentY = mouseY;
        let width = currentX - startPoint.x;
        let height = currentY - startPoint.y;
        
        ctx.strokeStyle = "red";
        ctx.lineWidth = 2;
        ctx.strokeRect(startPoint.x, startPoint.y, width, height);
    }

    // Draw mouse coordinates in pixels
    if (mouseX !== undefined && mouseY !== undefined) {
        ctx.fillStyle = "rgb(0,128,0)";
        ctx.font = "12px Arial";
        ctx.fillText(`(${Math.round(mouseX)}, ${Math.round(mouseY)})`, mouseX + 10, mouseY - 10);
    }
}

function onMouseMove(e) {
    let rect = canvas.getBoundingClientRect();
    mouseX = e.clientX - rect.left;
    mouseY = e.clientY - rect.top;
    drawCanvas();
}

function createTypeDropdown(defaultValue, onChangeCallback) {
    const select = document.createElement('select');
    select.className = 'type-select';
    const options = ['Beacon', 'Booth', 'Other'];
    
    options.forEach(option => {
        const optionElement = document.createElement('option');
        optionElement.value = option;
        optionElement.textContent = option;
        select.appendChild(optionElement);
    });
    
    select.value = defaultValue;
    select.addEventListener('change', onChangeCallback);
    return select;
}

function updatePOITable() {
    // Update beacon count
    document.getElementById("poiCount").textContent = `Total Beacons: ${pois.length}`;
    document.getElementById("poiCount").style.fontWeight = "normal";
    
    // Update POI table
    let poiTableBody = document.querySelector("#poiTable tbody");
    poiTableBody.innerHTML = "";
    pois.forEach(poi => {
        let row = document.createElement("tr");
        
        // ID Cell
        let idCell = document.createElement("td");
        idCell.textContent = poi.id;
        
        // Type Cell
        let typeCell = document.createElement("td");
        let typeSelect = createTypeDropdown(poi.type || 'Beacon', function() {
            poi.type = this.value;
        });
        typeCell.appendChild(typeSelect);
        
        // Name Cell
        let nameCell = document.createElement("td");
        let nameInput = document.createElement("input");
        nameInput.type = "text";
        nameInput.className = "name-input";
        nameInput.placeholder = "Enter name";
        nameInput.value = poi.name || "";
        nameInput.addEventListener("input", function() {
            poi.name = this.value;
        });
        nameCell.appendChild(nameInput);

        // Description Cell
        let descCell = document.createElement("td");
        let descInput = document.createElement("input");
        descInput.type = "text";
        descInput.className = "name-input";
        descInput.placeholder = "Enter description";
        descInput.value = poi.description || "";
        descInput.addEventListener("input", function() {
            poi.description = this.value;
        });
        descCell.appendChild(descInput);
        
        // Coordinates Cell (in pixels)
        let coordsCell = document.createElement("td");
        let coordsObj = {
            start: { x: Math.round(poi.x), y: Math.round(poi.y) },
            end: { x: Math.round(poi.x), y: Math.round(poi.y) }
        };
        coordsCell.textContent = JSON.stringify(coordsObj);

        // Center Coordinates Cell (in pixels)
        let centerCell = document.createElement("td");
        centerCell.textContent = `(${Math.round(poi.x)}, ${Math.round(poi.y)})`;
        
        // Append all cells in correct order
        row.appendChild(idCell);
        row.appendChild(typeCell);
        row.appendChild(nameCell);
        row.appendChild(descCell);
        row.appendChild(coordsCell);
        row.appendChild(centerCell);
        
        poiTableBody.appendChild(row);
    });
}

function updateBoothTable() {
    // Update booth count
    document.getElementById("boothCount").textContent = `Total POI: ${booths.length}`;
    
    let tableBody = document.querySelector("#boothTable tbody");
    tableBody.innerHTML = "";
    booths.forEach(booth => {
        let row = document.createElement("tr");
        
        // ID Cell
        let idCell = document.createElement("td");
        idCell.textContent = booth.id;
        
        // Type Cell
        let typeCell = document.createElement("td");
        let typeSelect = createTypeDropdown(booth.type || 'Booth', function() {
            booth.type = this.value;
        });
        typeCell.appendChild(typeSelect);
        
        // Name Cell
        let nameCell = document.createElement("td");
        let nameInput = document.createElement("input");
        nameInput.type = "text";
        nameInput.className = "name-input";
        nameInput.placeholder = "Enter name";
        nameInput.value = booth.name || "";
        nameInput.addEventListener("input", function() {
            booth.name = this.value;
        });
        nameCell.appendChild(nameInput);

        // Description Cell
        let descCell = document.createElement("td");
        let descInput = document.createElement("input");
        descInput.type = "text";
        descInput.className = "name-input";
        descInput.placeholder = "Enter description";
        descInput.value = booth.description || "";
        descInput.addEventListener("input", function() {
            booth.description = this.value;
        });
        descCell.appendChild(descInput);
        
        // Get start and end coordinates in pixels
        let startX_px = booth.start ? booth.start.x : booth.points[0].x;
        let startY_px = booth.start ? booth.start.y : booth.points[0].y;
        let endX_px = booth.end ? booth.end.x : booth.points[2].x;
        let endY_px = booth.end ? booth.end.y : booth.points[2].y;
        
        // Coordinates Cell (in pixels)
        let coordsCell = document.createElement("td");
        let coordsObj = {
            start: { x: Math.round(startX_px), y: Math.round(startY_px) },
            end: { x: Math.round(endX_px), y: Math.round(endY_px) }
        };
        coordsCell.textContent = JSON.stringify(coordsObj);

        // Center Coordinates Cell (in pixels)
        let centerCell = document.createElement("td");
        let centerX_px = Math.round((startX_px + endX_px) / 2);
        let centerY_px = Math.round((startY_px + endY_px) / 2);
        centerCell.textContent = `(${centerX_px}, ${centerY_px})`;
        
        // Append all cells in correct order
        row.appendChild(idCell);
        row.appendChild(typeCell);
        row.appendChild(nameCell);
        row.appendChild(descCell);
        row.appendChild(coordsCell);
        row.appendChild(centerCell);
        
        tableBody.appendChild(row);
    });
}

function computeBoundingBox(points) {
    let xs = points.map(pt => pt.x);
    let ys = points.map(pt => pt.y);
    let x = Math.min(...xs);
    let y = Math.min(...ys);
    let w = Math.max(...xs) - x;
    let h = Math.max(...ys) - y;
    return { x: x, y: y, w: w, h: h };
}

function computeFontSize(boxWidth, boxHeight, text) {
    let base = Math.min(boxWidth, boxHeight);
    let size = base / 5;
    return Math.max(size, 10);
}

function updateAllInputValues() {
    // Update POI table values
    const poiRows = document.querySelectorAll("#poiTable tbody tr");
    poiRows.forEach(row => {
        const id = parseInt(row.cells[0].textContent);
        const poi = pois.find(p => p.id === id);
        if (poi) {
            poi.name = row.cells[2].querySelector("input").value || "";
            poi.description = row.cells[3].querySelector("input").value || "No Description";
        }
    });

    // Update booth table values
    const boothRows = document.querySelectorAll("#boothTable tbody tr");
    boothRows.forEach(row => {
        const id = parseInt(row.cells[0].textContent);
        const booth = booths.find(b => b.id === id);
        if (booth) {
            booth.name = row.cells[2].querySelector("input").value || "";
            booth.description = row.cells[3].querySelector("input").value || "No Description";
        }
    });
}

function generateCSV() {
    // Create and add CSV download link for POI coordinates
    let csvContent = "ID,Type,Name,Description,Coordinates,Center Coordinates\n";
    
    // Add booth records to CSV
    booths.forEach(booth => {
        // Get coordinates in pixels
        let startX_px = booth.start ? booth.start.x : booth.points[0].x;
        let startY_px = booth.start ? booth.start.y : booth.points[0].y;
        let endX_px = booth.end ? booth.end.x : booth.points[2].x;
        let endY_px = booth.end ? booth.end.y : booth.points[2].y;
        
        // Round pixel values
        startX_px = Math.round(startX_px);
        startY_px = Math.round(startY_px);
        endX_px = Math.round(endX_px);
        endY_px = Math.round(endY_px);
        
        // Calculate center coordinates in pixels
        let centerX_px = Math.round((startX_px + endX_px) / 2);
        let centerY_px = Math.round((startY_px + endY_px) / 2);
        
        // Create coordinates string without JSON.stringify
        let coordsStr = `{start:{x:${startX_px},y:${startY_px}},end:{x:${endX_px},y:${endY_px}}}`;
        
        // Create CSV row with escaped fields
        let row = [
            booth.id,
            `"${booth.type || 'Booth'}"`,
            `"${(booth.name || '').replace(/"/g, '""')}"`,
            `"${(booth.description || '').replace(/"/g, '""')}"`,
            `"${coordsStr}"`,
            `"(${centerX_px}, ${centerY_px})"`
        ].join(',');
        
        csvContent += row + '\n';
    });

    // Add beacon records to CSV
    pois.forEach(poi => {
        // Round pixel values
        let x_px = Math.round(poi.x);
        let y_px = Math.round(poi.y);
        
        // Create coordinates string without JSON.stringify
        let coordsStr = `{start:{x:${x_px},y:${y_px}},end:{x:${x_px},y:${y_px}}}`;
        
        // Create CSV row with escaped fields
        let row = [
            poi.id,
            `"${poi.type || 'Beacon'}"`,
            `"${(poi.name || '').replace(/"/g, '""')}"`,
            `"${(poi.description || '').replace(/"/g, '""')}"`,
            `"${coordsStr}"`,
            `"(${x_px}, ${y_px})"`
        ].join(',');
        
        csvContent += row + '\n';
    });

    // Create download link
    let csvBlob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
    let csvUrl = URL.createObjectURL(csvBlob);
    let csvLink = document.getElementById("csvDownloadLink");
    const eventName = document.getElementById("floorplanTitle").textContent;
    csvLink.href = csvUrl;
    csvLink.download = `${eventName}_poi_coordinates.csv`;
}

function finishDrawing() {
    // Update all input values before generating CSV
    updateAllInputValues();
    // Generate new CSV
    generateCSV();
    gridOn = false;
    drawCanvas();
    let dataURL = canvas.toDataURL("image/png");
    let downloadLink = document.getElementById("downloadLink");
    downloadLink.href = dataURL;
    const eventName = document.getElementById("floorplanTitle").textContent;
    downloadLink.download = `${eventName}_annotated_floorplan.png`;
    
    // Update tables
    updateBoothTable();
    updatePOITable();
}

function clearDrawings() {
    booths = [];
    pois = [];
    elementCounter = 0; // Reset the single counter
    currentPoints = [];
    startPoint = null;
    // Clear tables and counts
    document.querySelector("#boothTable tbody").innerHTML = "";
    document.querySelector("#poiTable tbody").innerHTML = "";
    document.getElementById("poiCount").textContent = "Total Beacons: 0";
    document.getElementById("boothCount").textContent = "Total POI: 0";
    drawCanvas();
}

async function generateReport() {
    // Ensure all inputs are up to date before generating the report
    updateAllInputValues();
    
    // Get the floorplan title
    const eventName = document.getElementById("floorplanTitle").textContent || "Untitled Floorplan";
    
    // Create new PDF document
    const { jsPDF } = window.jspdf;
    const doc = new jsPDF('p', 'mm', 'a4');
    
    // First page - Title and information
    doc.setFontSize(24);
    doc.text('InMaps', 105, 20, { align: 'center' });
    
    doc.setFontSize(18);
    doc.text('Floorplan Evaluation', 105, 30, { align: 'center' });
    doc.text(eventName, 105, 40, { align: 'center' });
    
    doc.setFontSize(12);
    doc.text(`Floor Dimensions: ${floorWidth} m x ${floorHeight} m`, 20, 50);
    doc.text(`Drawing Mode: ${mode}`, 20, 55);
    if (mode === "uniform") {
        doc.text(`Booth Table Dimensions: ${boothWidth} m x ${boothHeight} m`, 20, 60);
    }
    
    // First page - Canvas image
    const canvas = document.getElementById('drawingCanvas');
    const canvasDataURL = canvas.toDataURL('image/png');
    
    // Calculate dimensions to fit the image on the page
    const pageWidth = doc.internal.pageSize.getWidth();
    const pageHeight = doc.internal.pageSize.getHeight();
    const imgWidth = pageWidth - 40; // 20mm margin on each side
    const imgHeight = (canvas.height * imgWidth) / canvas.width;
    
    // Add image to first page (adjust y position based on whether uniform mode info was added)
    const imageY = mode === "uniform" ? 70 : 65;
    doc.addImage(canvasDataURL, 'PNG', 20, imageY, imgWidth, imgHeight);
    
    // Add page number
    doc.setFontSize(10);
    doc.text('Page 1 of 2', pageWidth - 20, pageHeight - 10);
    
    // Second page - Tables
    doc.addPage();
    
    let yPosition = 20; // Starting y position for content
    
    // Add POI Records section
    doc.setFontSize(16);
    doc.text('POI Records', 10, yPosition);
    yPosition += 10;
    
    doc.setFontSize(12);
    doc.text(`Total POI: ${booths.length}`, 10, yPosition);
    yPosition += 10;
    
    // Create POI table
    const boothTable = document.getElementById('boothTable');
    await html2canvas(boothTable).then(canvas => {
        const imgData = canvas.toDataURL('image/png');
        const imgWidth = pageWidth - 20;
        const imgHeight = (canvas.height * imgWidth) / canvas.width;
        doc.addImage(imgData, 'PNG', 10, yPosition, imgWidth, imgHeight);
        yPosition += imgHeight + 10; // Reduced spacing after the table
    });
    
    // Add Beacon Records section
    doc.setFontSize(16);
    doc.text('Beacon Records', 10, yPosition);
    yPosition += 10;
    
    doc.setFontSize(12);
    doc.text(`Total Beacons: ${pois.length}`, 10, yPosition);
    yPosition += 10;
    
    // Create Beacon table
    const poiTable = document.getElementById('poiTable');
    await html2canvas(poiTable).then(canvas => {
        const imgData = canvas.toDataURL('image/png');
        const imgWidth = pageWidth - 20;
        const imgHeight = (canvas.height * imgWidth) / canvas.width;
        doc.addImage(imgData, 'PNG', 10, yPosition, imgWidth, imgHeight);
    });
    
    // Add page number
    doc.setFontSize(10);
    doc.text('Page 2 of 2', pageWidth - 20, pageHeight - 10);
    
    // Save the PDF with event name
    doc.save(`${eventName}_floorplan_report.pdf`);
}

async function generateZip() {
    try {
        // Ensure all inputs are up to date
        updateAllInputValues();
        
        const eventName = document.getElementById("floorplanTitle").textContent || "Untitled Floorplan";
        const zip = new JSZip();
        
        // Add the annotated floorplan image
        const canvas = document.getElementById('drawingCanvas');
        const imageData = canvas.toDataURL('image/png').split(',')[1];
        zip.file(`${eventName}_annotated_floorplan.png`, imageData, {base64: true});
        
        // Add the CSV file
        let csvContent = "ID,Type,Name,Description,Start_X,Start_Y,End_X,End_Y,Center Coordinates\n";
        
        // Add booth records to CSV
        booths.forEach(booth => {
            let startX_px = booth.start ? booth.start.x : booth.points[0].x;
            let startY_px = booth.start ? booth.start.y : booth.points[0].y;
            let endX_px = booth.end ? booth.end.x : booth.points[2].x;
            let endY_px = booth.end ? booth.end.y : booth.points[2].y;
            
            let startX_m = (startX_px * scaleX).toFixed(2);
            let startY_m = (startY_px * scaleY).toFixed(2);
            let endX_m = (endX_px * scaleX).toFixed(2);
            let endY_m = (endY_px * scaleY).toFixed(2);
            let centerX_m = ((parseFloat(startX_m) + parseFloat(endX_m)) / 2).toFixed(2);
            let centerY_m = ((parseFloat(startY_m) + parseFloat(endY_m)) / 2).toFixed(2);
            
            csvContent += `${booth.id},"${booth.type || 'Booth'}","${booth.name || ''}","${booth.description || ''}",${startX_m},${startY_m},${endX_m},${endY_m},"(${centerX_m}, ${centerY_m})"\n`;
        });

        pois.forEach(poi => {
            let x_m = (poi.x * scaleX).toFixed(2);
            let y_m = (poi.y * scaleY).toFixed(2);
            csvContent += `${poi.id},"${poi.type || 'Beacon'}","${poi.name || ''}","${poi.description || ''}",${x_m},${y_m},${x_m},${y_m},"(${x_m}, ${y_m})"\n`;
        });
        
        zip.file(`${eventName}_poi_coordinates.csv`, csvContent);
        
        // Generate and add the PDF
        const { jsPDF } = window.jspdf;
        const doc = new jsPDF('p', 'mm', 'a4');
        
        doc.setFontSize(24);
        doc.text('InMaps', 105, 20, { align: 'center' });
        
        doc.setFontSize(18);
        doc.text('Floorplan Evaluation', 105, 30, { align: 'center' });
        doc.text(eventName, 105, 40, { align: 'center' });
        
        doc.setFontSize(12);
        doc.text(`Floor Dimensions: ${floorWidth} m x ${floorHeight} m`, 20, 50);
        doc.text(`Drawing Mode: ${mode}`, 20, 55);
        if (mode === "uniform") {
            doc.text(`Booth Table Dimensions: ${boothWidth} m x ${boothHeight} m`, 20, 60);
        }
        
        const canvasDataURL = canvas.toDataURL('image/png');
        const pageWidth = doc.internal.pageSize.getWidth();
        const pageHeight = doc.internal.pageSize.getHeight();
        const imgWidth = pageWidth - 40;
        const imgHeight = (canvas.height * imgWidth) / canvas.width;
        
        const imageY = mode === "uniform" ? 70 : 65;
        doc.addImage(canvasDataURL, 'PNG', 20, imageY, imgWidth, imgHeight);
        
        doc.setFontSize(10);
        doc.text('Page 1 of 2', pageWidth - 20, pageHeight - 10);
        
        doc.addPage();
        
        let yPosition = 20;
        
        doc.setFontSize(16);
        doc.text('POI Records', 10, yPosition);
        yPosition += 10;
        
        doc.setFontSize(12);
        doc.text(`Total POI: ${booths.length}`, 10, yPosition);
        yPosition += 10;
        
        const boothTable = document.getElementById('boothTable');
        const boothCanvas = await html2canvas(boothTable);
        const boothImgData = boothCanvas.toDataURL('image/png');
        const boothImgWidth = pageWidth - 20;
        const boothImgHeight = (boothCanvas.height * boothImgWidth) / boothCanvas.width;
        doc.addImage(boothImgData, 'PNG', 10, yPosition, boothImgWidth, boothImgHeight);
        yPosition += boothImgHeight + 10;
        
        doc.setFontSize(16);
        doc.text('Beacon Records', 10, yPosition);
        yPosition += 10;
        
        doc.setFontSize(12);
        doc.text(`Total Beacons: ${pois.length}`, 10, yPosition);
        yPosition += 10;
        
        const poiTable = document.getElementById('poiTable');
        const poiCanvas = await html2canvas(poiTable);
        const poiImgData = poiCanvas.toDataURL('image/png');
        const poiImgWidth = pageWidth - 20;
        const poiImgHeight = (poiCanvas.height * poiImgWidth) / poiCanvas.width;
        doc.addImage(poiImgData, 'PNG', 10, yPosition, poiImgWidth, poiImgHeight);
        
        doc.setFontSize(10);
        doc.text('Page 2 of 2', pageWidth - 20, pageHeight - 10);
        
        // Add PDF to zip
        const pdfData = doc.output('arraybuffer');
        zip.file(`${eventName}_floorplan_report.pdf`, pdfData);
        
        // Generate the zip file
        const zipBlob = await zip.generateAsync({type: 'blob'});
        
        // Create download link and trigger download
        const downloadUrl = URL.createObjectURL(zipBlob);
        const a = document.createElement('a');
        a.href = downloadUrl;
        a.download = `${eventName}_floorplan_package.zip`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(downloadUrl);
    } catch (error) {
        console.error('Error generating zip:', error);
        alert('There was an error generating the zip file. Please try again.');
    }
}

// Update the event listener for zip download
document.getElementById("zipDownloadLink").addEventListener("click", async function(e) {
    e.preventDefault();
    await generateZip();
});

function showDetailsDialog(isBeacon) {
    const dialog = document.getElementById('detailsDialog');
    const title = document.getElementById('detailsDialogTitle');
    const typeSelect = document.getElementById('elementType');
    
    // Set dialog title based on element type
    title.textContent = isBeacon ? 'Beacon Details' : 'Booth Details';
    
    // Set default type
    typeSelect.value = isBeacon ? 'Beacon' : 'Booth';
    
    // Clear previous values
    document.getElementById('elementName').value = '';
    document.getElementById('elementDescription').value = '';
    
    // Show dialog
    dialog.style.display = 'block';
}

// Handle details dialog buttons
document.getElementById('saveDetails').addEventListener('click', function() {
    const dialog = document.getElementById('detailsDialog');
    const type = document.getElementById('elementType').value;
    const name = document.getElementById('elementName').value;
    const description = document.getElementById('elementDescription').value;
    
    if (currentElement) {
        currentElement.type = type;
        currentElement.name = name;
        currentElement.description = description;
        
        if (isDrawingPOI) {
            pois.push(currentElement);
            updatePOITable();
        } else {
            booths.push(currentElement);
            updateBoothTable();
        }
    }
    
    dialog.style.display = 'none';
    currentElement = null;
    drawCanvas();
});

document.getElementById('skipDetails').addEventListener('click', function() {
    const dialog = document.getElementById('detailsDialog');
    
    if (currentElement) {
        if (isDrawingPOI) {
            pois.push(currentElement);
            updatePOITable();
        } else {
            booths.push(currentElement);
            updateBoothTable();
        }
    }
    
    dialog.style.display = 'none';
    currentElement = null;
    drawCanvas();
});

document.getElementById('cancelDetails').addEventListener('click', function() {
    const dialog = document.getElementById('detailsDialog');
    dialog.style.display = 'none';
    currentElement = null;
    drawCanvas();
});

function onCanvasClick(e) {
    let rect = canvas.getBoundingClientRect();
    let clickPos = {
        x: e.clientX - rect.left,
        y: e.clientY - rect.top
    };
    
    if (isDrawingPOI) {
        elementCounter++;
        currentElement = { 
            id: elementCounter, 
            x: clickPos.x, 
            y: clickPos.y,
            type: 'Beacon',
            name: "",
            description: ""
        };
        showDetailsDialog(true);
    } else {
        if (mode === "arbitrary") {
            currentPoints.push(clickPos);
            if (currentPoints.length === 4) {
                elementCounter++;
                currentElement = { 
                    id: elementCounter, 
                    points: currentPoints.slice(),
                    type: 'Booth',
                    name: "",
                    description: ""
                };
                showDetailsDialog(false);
                currentPoints = [];
            }
        } else if (mode === "rectangle") {
            if (!startPoint) {
                startPoint = clickPos;
            } else {
                let endPoint = clickPos;
                elementCounter++;
                currentElement = { 
                    id: elementCounter, 
                    start: startPoint, 
                    end: endPoint,
                    type: 'Booth',
                    name: "",
                    description: ""
                };
                showDetailsDialog(false);
                startPoint = null;
            }
        } else if (mode === "uniform") {
            elementCounter++;
            let topLeft = clickPos;
            let endPoint = { 
                x: topLeft.x + uniformDims.width, 
                y: topLeft.y + uniformDims.height 
            };
            currentElement = { 
                id: elementCounter, 
                start: topLeft, 
                end: endPoint,
                type: 'Booth',
                name: "",
                description: ""
            };
            showDetailsDialog(false);
        }
    }
    drawCanvas();
}

// Handle uniform mode dialog confirmation
document.getElementById('confirmUniform').addEventListener('click', function() {
    const widthInput = document.getElementById('uniformWidth');
    const heightInput = document.getElementById('uniformHeight');
    
    // Validate inputs
    const width = parseFloat(widthInput.value);
    const height = parseFloat(heightInput.value);
    
    if (width < 0.1 || height < 0.1) {
        alert('Please enter valid dimensions (minimum 0.1 meters)');
        return;
    }
    
    // Update uniform dimensions in meters
    uniformWidth = width;
    uniformHeight = height;
    
    // Close the dialog
    document.getElementById('uniformModeDialog').style.display = 'none';
    
    // Update the mode selector and drawing mode
    document.getElementById('drawingModeSelect').value = 'uniform';
    updateDrawingMode('uniform');
});

// Handle uniform mode dialog cancellation
document.getElementById('cancelUniform').addEventListener('click', function() {
    // Close the dialog
    document.getElementById('uniformModeDialog').style.display = 'none';
    
    // Revert the mode selector to previous mode
    document.getElementById('drawingModeSelect').value = previousMode;
});

function updateDrawingMode(newMode) {
    // Reset current drawing state
    isDrawingPOI = false;
    currentPoints = [];
    startPoint = null;
    
    // Update the mode
    mode = newMode;
    
    // If switching to uniform mode, convert meters to pixels
    if (newMode === 'uniform') {
        uniformDims = {
            width: (uniformWidth / scaleX),
            height: (uniformHeight / scaleY)
        };
    }
    
    // Redraw the canvas
    drawCanvas();
}
