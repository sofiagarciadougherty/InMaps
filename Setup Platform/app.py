# from flask import Flask, render_template, request, url_for
# import os
# from werkzeug.utils import secure_filename

# app = Flask(__name__)
# app.config['UPLOAD_FOLDER'] = 'static/uploads'

# # Create the upload folder if it doesn't exist
# if not os.path.exists(app.config['UPLOAD_FOLDER']):
#     os.makedirs(app.config['UPLOAD_FOLDER'])

# @app.route('/', methods=['GET', 'POST'])
# def index():
#     if request.method == 'POST':
#         # Retrieve form data
#         floor_width = request.form.get('floor_width')
#         floor_height = request.form.get('floor_height')
#         mode = request.form.get('mode')
#         booth_width = request.form.get('booth_width')
#         booth_height = request.form.get('booth_height')
        
#         # Get the uploaded image file
#         file = request.files.get('floorplan_image')
#         if file:
#             filename = secure_filename(file.filename)
#             file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
#             file.save(file_path)
#         else:
#             file_path = None

#         return render_template('draw.html',
#                                floor_width=floor_width,
#                                floor_height=floor_height,
#                                mode=mode,
#                                booth_width=booth_width,
#                                booth_height=booth_height,
#                                image_url=url_for('static', filename='uploads/' + filename))
#     return render_template('index.html')

# if __name__ == '__main__':
#     app.run(debug=True)

from flask import Flask, render_template, request, url_for
import os
import math
import matplotlib.pyplot as plt
import matplotlib.image as mpimg
from matplotlib.patches import Circle, Rectangle
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = 'static/uploads'

# Create the upload folder if it doesn't exist
if not os.path.exists(app.config['UPLOAD_FOLDER']):
    os.makedirs(app.config['UPLOAD_FOLDER'])

def compute_edge_aligned_beacon_positions(width, height, r):
    dx = math.sqrt(3) * r
    dy = 1.5 * r

    positions = set()
    row = 0
    y = 0

    while y <= height + r:
        offset = 0 if row % 2 == 0 else dx / 2
        x = offset
        while x <= width + r:
            adjusted_x = min(max(x, 0), width)
            adjusted_y = min(max(y, 0), height)
            positions.add((round(adjusted_x, 2), round(adjusted_y, 2)))
            x += dx
        row += 1
        y = row * dy

    if len(positions) < 3:
        triangle = []
        cx = width / 2
        cy = height / 2
        side = min(width, height) / 2
        triangle.append((cx, cy + side / math.sqrt(3)))
        triangle.append((cx - side / 2, cy - side / (2 * math.sqrt(3))))
        triangle.append((cx + side / 2, cy - side / (2 * math.sqrt(3))))
        for pt in triangle:
            positions.add((round(pt[0], 2), round(pt[1], 2)))

    return list(positions)

def visualize_edge_aligned_beacons(width, height, positions, floorplan_path, output_path):
    """
    Visualize beacon placement using the final annotated floorplan as background.
    """
    try:
        img = mpimg.imread(floorplan_path)
        
        dpi = 100
        img_height, img_width = img.shape[0], img.shape[1]
        figsize = img_width / dpi, img_height / dpi

        fig, ax = plt.subplots(figsize=figsize, dpi=dpi)
        ax.imshow(img)
        ax.axis('off')

        # Coordinate scaling
        scale_x = img_width / width
        scale_y = img_height / height

        # Adjust dot placement: invert Y to match top-left image origin
        for x, y in positions:
            img_x = x * scale_x
            img_y = img_height - (y * scale_y)
            ax.plot(img_x, img_y, 'ro', markersize=4)

        plt.subplots_adjust(left=0, right=1, top=1, bottom=0)
        plt.savefig(output_path, bbox_inches='tight', pad_inches=0)
        plt.close(fig)
        
    except FileNotFoundError:
        print(f"Image file not found: {floorplan_path}")

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        # Retrieve form data
        floor_width = float(request.form.get('floor_width'))
        floor_height = float(request.form.get('floor_height'))
        mode = request.form.get('mode')
        booth_width = request.form.get('booth_width')
        booth_height = request.form.get('booth_height')
        floorplan_title = request.form.get('floorplanTitle', '')
        
        # Get the uploaded image file
        file = request.files.get('floorplan_image')
        if file:
            # Save original image
            filename = secure_filename(file.filename)
            file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            file.save(file_path)
            
            # Generate beacon positions and create annotated image
            positions = compute_edge_aligned_beacon_positions(floor_width, floor_height, r=15)
            annotated_filename = 'annotated_' + filename
            annotated_path = os.path.join(app.config['UPLOAD_FOLDER'], annotated_filename)
            visualize_edge_aligned_beacons(floor_width, floor_height, positions, file_path, annotated_path)
            
            # Use the annotated image for display
            display_image = url_for('static', filename='uploads/' + annotated_filename)
        else:
            display_image = None

        return render_template('draw.html',
                           floor_width=floor_width,
                           floor_height=floor_height,
                           mode=mode,
                           booth_width=booth_width,
                           booth_height=booth_height,
                           floorplan_title=floorplan_title,
                           image_url=display_image)
    return render_template('index.html')

if __name__ == '__main__':
    app.run(debug=True)

