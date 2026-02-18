// IKEA 32x32cm frame — 3D printed backplate for Inky Impression 13.3"
// All dimensions in mm
//
// === Assembly (front to back) ===
// 1. IKEA frame (glass + wood border)
// 2. Paper mat with 200x200mm opening (original IKEA mat, reused)
// 3. Display board (screen faces forward through mat opening)
// 4. 3D printed backplate (this model — replaces original hardboard)
// 5. IKEA metal clips (original clips hold everything in the frame)
//
// === Design intent ===
// The 3D printed backplate replaces the IKEA hardboard. It must be the
// same thickness (~3mm) so the original metal clips can still secure it.
// The display board sits INSIDE a recess in the backplate, held by ledges
// that grip the board edges. The board's viewable area is centered in the
// mat's 200x200 opening. Since the viewable area is offset on the board,
// the board itself is not centered in the backplate.
//
// The display image is square, so the 200x200 mat opening is intentional.
// Horizontally ~35mm of display is hidden behind the mat on each side.
// Vertically ~1.4mm is hidden on each side (nearly perfect fit).
//
// The back side of the board has a Raspberry Pi and other components.
// Nothing covers the back — components face outward. A stand will be
// added later so the frame can lean on a surface. Battery holder TBD.
//
// === Print constraints ===
// Bambu Lab A1 Mini build volume: 180x180x180mm.
// The 320x320mm backplate is split into 4 interlocking quadrants
// (~160x160mm each) with puzzle-style edges for assembly.
//
// === TODO (measure later) ===
// - Board thickness assumed 1.6mm (standard PCB) — measure actual
// - Back-side component heights unknown — no clearance modeled yet
// - Backplate thickness assumed 3mm — measure original IKEA hardboard

// --- IKEA Frame ---
frame_size = 320.00;
frame_thickness = 3.00; // must match original hardboard for metal clips

// Mat opening (centered in frame)
mat_opening = 200.00;
mat_offset = (frame_size - mat_opening) / 2; // 60mm from each edge

// --- Display board (Pimoroni Inky Impression 13.3") ---
board_width  = 296.70;
board_height = 210.00;
board_thickness = 1.6; // TODO: measure actual board thickness

// Corner mounting holes
hole_inset    = 3.00;  // from board edge to hole center
hole_diameter = 2.7;   // M2.5 clearance hole (adjust if needed)
hole_radius = hole_diameter / 2;

// Corner rounding (estimated, not dimensioned in schematic)
corner_radius = 2.0;

// Viewable area (not centered on board — connector side has more margin)
viewable_width  = 270.40;
viewable_height = 202.80;
viewable_x = 9.00;  // 9mm from left edge of board
viewable_y = (board_height - viewable_height) / 2; // 3.60mm top and bottom

// --- Board positioning (viewable area centered in mat opening) ---
viewable_center_x = viewable_x + viewable_width / 2;  // 144.20
viewable_center_y = viewable_y + viewable_height / 2;  // 105.00
mat_center = frame_size / 2; // 160.00
board_x = mat_center - viewable_center_x; // 15.80
board_y = mat_center - viewable_center_y; // 55.00

// --- Board recess ---
// The board sits inside a pocket in the backplate. The recess goes
// through most of the thickness, leaving a thin ledge to support
// the board from the front side.
recess_clearance = 0.3; // printer tolerance on each side
recess_width  = board_width + 2 * recess_clearance;
recess_height = board_height + 2 * recess_clearance;
recess_depth  = board_thickness; // TODO: adjust when real thickness known
ledge_width   = 2.0; // how much the ledge overlaps the board edge

// --- Puzzle interlock ---
// Tabs must be in solid border areas (outside the board through-hole).
// Solid zones: bottom (y < ~54.7), top (y > ~265.3),
//              left (x < ~15.5, narrow), right (x > ~312.8, too narrow).
tab_width  = 20.0;
tab_depth  = 5.0;
tab_small  = 12.0; // smaller tab for narrow borders
half = frame_size / 2; // 160mm — split point for quadrants

// Recess boundaries (for tab placement reference)
recess_y_min = board_y - recess_clearance;           // ~54.70
recess_y_max = recess_y_min + recess_height;         // ~265.30
recess_x_min = board_x - recess_clearance;           // ~15.50

// Tab positions — centered in solid border zones
vtab_y_bot = recess_y_min / 2;                       // ~27.35 (bottom border)
vtab_y_top = (recess_y_max + frame_size) / 2;        // ~292.65 (top border)
htab_x_left = recess_x_min / 2;                      // ~7.75 (left border)

// --- Modules ---

module board() {
    hole_positions = [
        [hole_inset, hole_inset],
        [board_width - hole_inset, hole_inset],
        [hole_inset, board_height - hole_inset],
        [board_width - hole_inset, board_height - hole_inset],
    ];

    difference() {
        linear_extrude(height = board_thickness)
            offset(r = corner_radius)
            offset(delta = -corner_radius)
            square([board_width, board_height]);

        for (pos = hole_positions) {
            translate([pos[0], pos[1], -0.1])
                cylinder(h = board_thickness + 0.2, r = hole_radius, $fn = 32);
        }
    }
}

// --- 2D quadrant boundary with puzzle edges ---
// qx: 0=left, 1=right  qy: 0=bottom, 1=top
//
// Vertical split (x=160): tabs in bottom and top solid borders.
//   Left quadrants (qx==0) own the tabs, right quadrants get slots.
// Horizontal split (y=160): tab in left solid border only.
//   Bottom quadrants (qy==0) own the tab, top quadrants get slot.
//   Right border is too narrow (~7mm) for a tab — omitted.

module puzzle_tab_2d(w = tab_width) {
    neck_width = w * 0.6;
    square([tab_depth, neck_width], center = true);
    translate([tab_depth / 2, 0])
        circle(d = w, $fn = 48);
}

module puzzle_slot_2d(w = tab_width) {
    offset(delta = recess_clearance) {
        neck_width = w * 0.6;
        square([tab_depth, neck_width], center = true);
        translate([tab_depth / 2, 0])
            circle(d = w, $fn = 48);
    }
}

module quadrant_2d(qx, qy) {
    // Vertical split tab y-position for this quadrant's half
    vtab_y = (qy == 0) ? vtab_y_bot : vtab_y_top;

    difference() {
        union() {
            // Base square for this quadrant
            translate([qx * half, qy * half])
                square([half, half]);

            // Left quadrants (qx==0): add tab on right edge
            // (one tab per quadrant, in that quadrant's solid border)
            if (qx == 0)
                translate([half, vtab_y])
                    puzzle_tab_2d();

            // Bottom quadrants (qy==0): add small tab on top edge
            // (only in the narrow left border zone)
            if (qy == 0 && qx == 0)
                translate([htab_x_left, half])
                    rotate([0, 0, 90])
                    puzzle_tab_2d(tab_small);
        }

        // Right quadrants (qx==1): cut slot on left edge
        if (qx == 1)
            translate([half, vtab_y])
                puzzle_slot_2d();

        // Top-left quadrant (qx==0, qy==1): cut slot on bottom edge
        if (qy == 1 && qx == 0)
            translate([htab_x_left, half])
                rotate([0, 0, 90])
                puzzle_slot_2d(tab_small);
    }
}

// --- Full backplate (before splitting) ---

module backplate_solid() {
    difference() {
        // Full backplate slab
        linear_extrude(height = frame_thickness)
            square([frame_size, frame_size]);

        // Board recess — pocket from the front (display drops in)
        translate([
            board_x - recess_clearance,
            board_y - recess_clearance,
            frame_thickness - recess_depth
        ])
            linear_extrude(height = recess_depth + 0.1)
            square([recess_width, recess_height]);

        // Through-hole for display visibility — smaller than recess
        // so the ledge (recess minus this opening) supports the board
        translate([
            board_x + ledge_width,
            board_y + ledge_width,
            -0.1
        ])
            linear_extrude(height = frame_thickness + 0.2)
            square([
                board_width - 2 * ledge_width,
                board_height - 2 * ledge_width
            ]);
    }
}

// --- Quadrant: slice of backplate with puzzle edges ---

module quadrant(qx, qy) {
    intersection() {
        backplate_solid();
        linear_extrude(height = frame_thickness + 1)
            quadrant_2d(qx, qy);
    }
}

// --- Assembly view ---
// Set show_split=true to see the 4 quadrants separated,
// show_split=false to see them assembled.

show_split = true;
split_gap  = 5; // visual gap between quadrants when split

module placed_quadrant(qx, qy, col) {
    offset = show_split
        ? [(qx - 0.5) * split_gap, (qy - 0.5) * split_gap, 0]
        : [0, 0, 0];
    translate(offset)
        color(col) quadrant(qx, qy);
}

placed_quadrant(0, 0, "White");      // Q1 bottom-left
placed_quadrant(1, 0, "WhiteSmoke"); // Q2 bottom-right
placed_quadrant(0, 1, "WhiteSmoke"); // Q3 top-left
placed_quadrant(1, 1, "White");      // Q4 top-right

// Board sitting in the recess (for visualization only)
translate([board_x, board_y, frame_thickness - recess_depth])
    color("SteelBlue") board();

// Viewable area indicator
translate([
    board_x + viewable_x,
    board_y + viewable_y,
    frame_thickness - recess_depth + board_thickness - 0.01
])
    color("DarkSlateGray")
    linear_extrude(height = 0.02)
    square([viewable_width, viewable_height]);
